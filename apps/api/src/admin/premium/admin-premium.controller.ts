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
  UseGuards,
} from "@nestjs/common";
import { createZodDto, ZodResponse } from "nestjs-zod";
import {
  adminGrantPremiumBodySchema,
  adminPremiumSyncResponseSchema,
  adminUserPremiumSchema,
  type AdminPremiumSyncResponse,
  type AdminUserPremium,
} from "@repo/contracts";
import { AuthService } from "@repo/core/auth";
import { SubscriptionsService } from "@repo/core/subscriptions";
import { AdminGuard } from "../../auth/admin.guard.js";
import { SessionGuard } from "../../auth/session.guard.js";
import { RequestId } from "../../common/request-id.decorator.js";
import { Audited, CurrentAuditDraft, type AuditDraft } from "../audit/audited.decorator.js";
import { AdminReasonBodyDto } from "../sanctions/admin-reason-body.dto.js";
import { AdminPremiumAssembler } from "./admin-premium-assembler.js";

class AdminUserPremiumDto extends createZodDto(adminUserPremiumSchema) {}
class AdminGrantPremiumBodyDto extends createZodDto(adminGrantPremiumBodySchema) {}
class AdminPremiumSyncResponseDto extends createZodDto(adminPremiumSyncResponseSchema) {}

/**
 * `/v1/admin/users/:id/premium*` (ADR-038 §12, §17): the user sheet's « Premium » section, read
 * in our tables only, and its three actions through RevenueCat's API v2. None is a Sanction: no
 * e-mail. Without RevenueCat the actions answer `503 revenuecat_not_configured`; a RevenueCat
 * failure answers `502 revenuecat_unavailable`. `404 user_not_found` for an unknown account.
 */
@Controller("admin/users")
@UseGuards(SessionGuard, AdminGuard)
export class AdminPremiumController {
  constructor(
    private readonly auth: AuthService,
    private readonly subscriptions: SubscriptionsService,
    private readonly assembler: AdminPremiumAssembler,
  ) {}

  /** State, detail, history of RevenueCat events, link to RevenueCat, and whether it is configured. */
  @Get(":id/premium")
  @ZodResponse({ status: 200, type: AdminUserPremiumDto })
  async premium(@Param("id", ParseUUIDPipe) id: string): Promise<AdminUserPremium> {
    await this.auth.getAccountForAdmin(id);
    return this.assembler.premium(id);
  }

  /** « Resynchroniser »: queues `sync-subscription` (`queued: false` when one is already waiting). */
  @Post(":id/premium/sync")
  @HttpCode(HttpStatus.ACCEPTED)
  @Audited("premium.sync", { reason: "none" })
  @ZodResponse({ status: 202, type: AdminPremiumSyncResponseDto })
  async sync(
    @Param("id", ParseUUIDPipe) id: string,
    @RequestId() requestId: string | undefined,
  ): Promise<AdminPremiumSyncResponse> {
    await this.auth.getAccountForAdmin(id);
    return { queued: await this.subscriptions.requestSync(id, requestId) };
  }

  /**
   * « Offrir le Premium » for 1, 3, 6 or 12 months, any account (admin or banned included);
   * offering again replaces the end date. The webhook then syncs the row.
   */
  @Post(":id/premium/promotional")
  @HttpCode(HttpStatus.NO_CONTENT)
  @Audited("premium.grant", { reason: "required" })
  async grant(
    @Param("id", ParseUUIDPipe) id: string,
    @Body() body: AdminGrantPremiumBodyDto,
    @RequestId() requestId: string | undefined,
    @CurrentAuditDraft() audit: AuditDraft,
  ): Promise<void> {
    await this.auth.getAccountForAdmin(id);
    const expiresAt = await this.subscriptions.grantPromotionalPremium(id, body.duration, requestId);
    audit.details = { duration: body.duration, expiresAt: expiresAt.toISOString() };
  }

  /** « Retirer le Premium offert », at once; an App Store subscription is never touched. */
  @Delete(":id/premium/promotional")
  @HttpCode(HttpStatus.NO_CONTENT)
  @Audited("premium.revoke", { reason: "required" })
  async revoke(
    @Param("id", ParseUUIDPipe) id: string,
    @Body() _body: AdminReasonBodyDto,
    @RequestId() requestId: string | undefined,
  ): Promise<void> {
    await this.auth.getAccountForAdmin(id);
    await this.subscriptions.revokePromotionalPremium(id, requestId);
  }
}
