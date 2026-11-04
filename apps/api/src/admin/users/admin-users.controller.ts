import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseUUIDPipe,
  Post,
  Put,
  Query,
  Req,
  UseGuards,
} from "@nestjs/common";
import { fromNodeHeaders } from "better-auth/node";
import type { Request } from "express";
import { createZodDto, ZodResponse } from "nestjs-zod";
import {
  BAN_DURATION_SECONDS,
  adminBanBodySchema,
  adminRoleBodySchema,
  adminUserDetailSchema,
  adminUserListQuerySchema,
  adminUserListResponseSchema,
  adminUserReportsResponseSchema,
  adminUserSessionsResponseSchema,
  type AdminUserDetail,
  type AdminUserListResponse,
  type AdminUserReportsResponse,
  type AdminUserSessionsResponse,
} from "@repo/contracts";
import { AuthService, type ActiveBan } from "@repo/core/auth";
import { UsersService } from "@repo/core/users";
import { AccountDeletion } from "../../account-deletion/account-deletion.js";
import { AdminGuard } from "../../auth/admin.guard.js";
import { CurrentUser } from "../../auth/current-user.decorator.js";
import { SessionGuard, type AuthenticatedUser } from "../../auth/session.guard.js";
import { RequestId } from "../../common/request-id.decorator.js";
import { Audited, CurrentAuditDraft, type AuditDraft } from "../audit/audited.decorator.js";
import { AdminReasonBodyDto } from "../sanctions/admin-reason-body.dto.js";
import { SanctionNotices, type SanctionNotice } from "../sanctions/sanction-notices.js";
import { AdminUserAssembler } from "./admin-user-assembler.js";

class AdminUserListQueryDto extends createZodDto(adminUserListQuerySchema) {}
class AdminUserListResponseDto extends createZodDto(adminUserListResponseSchema) {}
class AdminUserDetailDto extends createZodDto(adminUserDetailSchema) {}
class AdminUserSessionsResponseDto extends createZodDto(adminUserSessionsResponseSchema) {}
class AdminUserReportsResponseDto extends createZodDto(adminUserReportsResponseSchema) {}
class AdminBanBodyDto extends createZodDto(adminBanBodySchema) {}
class AdminRoleBodyDto extends createZodDto(adminRoleBodySchema) {}

/**
 * `/v1/admin/users/*` (ADR-038 §5, §6, §17): the list, the user sheet's reads, the Sanctions on an
 * account and the admin role. Ban, unban, sign-out and role go through the admin plugin with the
 * Administrator's request headers (`AuthService`). Every Sanction but « Déconnecter partout »
 * hands its e-mail to {@link SanctionNotices}.
 *
 * `DELETE :id` (« Supprimer le compte ») goes through the one deletion service, {@link AccountDeletion}.
 */
@Controller("admin/users")
@UseGuards(SessionGuard, AdminGuard)
export class AdminUsersController {
  constructor(
    private readonly auth: AuthService,
    private readonly users: UsersService,
    private readonly assembler: AdminUserAssembler,
    private readonly notices: SanctionNotices,
    private readonly deletion: AccountDeletion,
  ) {}

  /** Search, filters and sort; newest sign-up first by default. */
  @Get()
  @ZodResponse({ status: 200, type: AdminUserListResponseDto })
  list(@Query() query: AdminUserListQueryDto): Promise<AdminUserListResponse> {
    return this.assembler.list(query);
  }

  /** The sheet's header, account, athlete profile, Activity and Follows. */
  @Get(":id")
  @ZodResponse({ status: 200, type: AdminUserDetailDto })
  detail(@Param("id", ParseUUIDPipe) id: string): Promise<AdminUserDetail> {
    return this.assembler.detail(id);
  }

  /** Open sessions: device, opening, expiry. */
  @Get(":id/sessions")
  @ZodResponse({ status: 200, type: AdminUserSessionsResponseDto })
  sessions(@Param("id", ParseUUIDPipe) id: string, @Req() request: Request): Promise<AdminUserSessionsResponse> {
    return this.assembler.sessions(fromNodeHeaders(request.headers), id);
  }

  /** Reports received and sent, each linking to its case. */
  @Get(":id/reports")
  @ZodResponse({ status: 200, type: AdminUserReportsResponseDto })
  reports(@Param("id", ParseUUIDPipe) id: string): Promise<AdminUserReportsResponse> {
    return this.assembler.reports(id);
  }

  /** Sanction: Ban for 24 h, 7 days, 30 days or for good; banning again replaces it. */
  @Post(":id/ban")
  @HttpCode(HttpStatus.NO_CONTENT)
  @Audited("user.ban", { reason: "required" })
  async ban(
    @Param("id", ParseUUIDPipe) id: string,
    @Body() body: AdminBanBodyDto,
    @Req() request: Request,
    @CurrentAuditDraft() audit: AuditDraft,
  ): Promise<void> {
    const seconds = body.duration === "permanent" ? null : BAN_DURATION_SECONDS[body.duration];
    const ban = await this.auth.banUser(fromNodeHeaders(request.headers), id, body.reason, seconds);
    audit.details = { duration: body.duration };
    await this.notify(audit, "user.ban", id, body.reason, { ban: toNoticeBan(ban) });
  }

  /** Sanction: lifts the Ban at once. */
  @Post(":id/unban")
  @HttpCode(HttpStatus.NO_CONTENT)
  @Audited("user.unban", { reason: "required" })
  async unban(
    @Param("id", ParseUUIDPipe) id: string,
    @Body() body: AdminReasonBodyDto,
    @Req() request: Request,
    @CurrentAuditDraft() audit: AuditDraft,
  ): Promise<void> {
    const lifted = await this.auth.unbanUser(fromNodeHeaders(request.headers), id);
    await this.notify(audit, "user.unban", id, body.reason, { ban: toNoticeBan(lifted) });
  }

  /** Sanction « Déconnecter partout »: no e-mail (ADR-038 §4). */
  @Post(":id/sign-out")
  @HttpCode(HttpStatus.NO_CONTENT)
  @Audited("user.sign_out", { reason: "required" })
  async signOut(
    @Param("id", ParseUUIDPipe) id: string,
    @Body() _body: AdminReasonBodyDto,
    @Req() request: Request,
  ): Promise<void> {
    await this.auth.revokeUserSessions(fromNodeHeaders(request.headers), id);
  }

  /** Sanction: first name « Athlète », empty last name. */
  @Post(":id/reset-name")
  @HttpCode(HttpStatus.NO_CONTENT)
  @Audited("user.name.reset", { reason: "required" })
  async resetName(
    @Param("id", ParseUUIDPipe) id: string,
    @Body() body: AdminReasonBodyDto,
    @CurrentAuditDraft() audit: AuditDraft,
  ): Promise<void> {
    // Read before the reset: the e-mail greets the athlete by the first name they chose.
    const recipient = await this.notices.recipientOf(id);
    const name = await this.users.resetName(id);
    await this.auth.setName(id, name);
    await this.notify(audit, "user.name.reset", id, body.reason, { profileField: "name", recipient });
  }

  /** Sanction: the bio emptied. */
  @Post(":id/reset-bio")
  @HttpCode(HttpStatus.NO_CONTENT)
  @Audited("user.bio.reset", { reason: "required" })
  async resetBio(
    @Param("id", ParseUUIDPipe) id: string,
    @Body() body: AdminReasonBodyDto,
    @CurrentAuditDraft() audit: AuditDraft,
  ): Promise<void> {
    await this.auth.getAccountForAdmin(id);
    await this.users.resetBio(id);
    await this.notify(audit, "user.bio.reset", id, body.reason, { profileField: "bio" });
  }

  /** Sanction: the Avatar removed, its object deleted; initials shown. */
  @Post(":id/reset-avatar")
  @HttpCode(HttpStatus.NO_CONTENT)
  @Audited("user.avatar.reset", { reason: "required" })
  async resetAvatar(
    @Param("id", ParseUUIDPipe) id: string,
    @Body() body: AdminReasonBodyDto,
    @CurrentAuditDraft() audit: AuditDraft,
  ): Promise<void> {
    await this.auth.getAccountForAdmin(id);
    await this.users.removeAvatar(id);
    await this.notify(audit, "user.avatar.reset", id, body.reason, { profileField: "avatar" });
  }

  /**
   * Sanction « Supprimer le compte » (ADR-038 §13): immediate and final, confirmed in the
   * backoffice by typing the athlete's name. Sends « Votre compte Nervo a été supprimé » with the
   * reason itself (not through {@link SanctionNotices}: the account is gone once it returns).
   * `409 user_is_admin` for an Administrator.
   */
  @Delete(":id")
  @HttpCode(HttpStatus.NO_CONTENT)
  @Audited("user.delete", { reason: "required" })
  async remove(
    @Param("id", ParseUUIDPipe) id: string,
    @Body() body: AdminReasonBodyDto,
    @Req() request: Request,
    @RequestId() requestId: string | undefined,
    @CurrentAuditDraft() audit: AuditDraft,
  ): Promise<void> {
    audit.details = { origin: "admin" };
    await this.deletion.deleteAsSanction({
      headers: fromNodeHeaders(request.headers),
      userId: id,
      reason: body.reason,
      auditEntryId: audit.entryId,
      requestId,
    });
  }

  /**
   * Grants (`user.role.grant`) or removes (`user.role.revoke`) the admin role; optional reason,
   * not a Sanction. `409` for no change or a self-demotion.
   */
  @Put(":id/role")
  @HttpCode(HttpStatus.NO_CONTENT)
  @Audited("user.role.grant", { reason: "optional" })
  async setRole(
    @Param("id", ParseUUIDPipe) id: string,
    @Body() body: AdminRoleBodyDto,
    @Req() request: Request,
    @CurrentUser() actor: AuthenticatedUser,
    @CurrentAuditDraft() audit: AuditDraft,
  ): Promise<void> {
    await this.auth.setRole(fromNodeHeaders(request.headers), actor.userId, id, body.role);
    audit.action = body.role === "admin" ? "user.role.grant" : "user.role.revoke";
  }

  private notify(
    audit: AuditDraft,
    action: SanctionNotice["action"],
    athleteId: string,
    reason: string,
    extra: Pick<SanctionNotice, "ban" | "profileField" | "recipient">,
  ): Promise<void> {
    return this.notices.send({
      auditEntryId: audit.entryId,
      action,
      athleteId,
      reason,
      activity: null,
      comment: null,
      ...extra,
    });
  }
}

function toNoticeBan(ban: ActiveBan): { until: string | null } {
  return { until: ban.until?.toISOString() ?? null };
}
