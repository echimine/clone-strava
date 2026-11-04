import { Body, Controller, HttpCode, HttpStatus, Post, UseGuards } from "@nestjs/common";
import { ApiResponse } from "@nestjs/swagger";
import { Throttle } from "@nestjs/throttler";
import { createZodDto } from "nestjs-zod";
import { accountDeletionRequestSchema } from "@repo/contracts";
import { AccountDeletion } from "../account-deletion/account-deletion.js";
import { CurrentUser } from "../auth/current-user.decorator.js";
import { SessionGuard, type AuthenticatedUser } from "../auth/session.guard.js";
import { RequestId } from "../common/request-id.decorator.js";

class AccountDeletionRequestDto extends createZodDto(accountDeletionRequestSchema) {}

/**
 * « Supprimer mon compte » (ADR-038 §13): immediate and final, re-verified by a Sign-in code sent
 * to the account's e-mail (Google accounts included). `403 admin_cannot_delete_account` for an
 * Administrator; a banned athlete has no session, so no access.
 */
@Controller("me/account-deletion")
@UseGuards(SessionGuard)
export class MeAccountDeletionController {
  constructor(private readonly deletion: AccountDeletion) {}

  /** Sends the Sign-in code to the account's address; 3 per minute, like the plugin's own route. */
  @Post("code")
  @Throttle({ default: { ttl: 60_000, limit: 3 } })
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiResponse({ status: 204, description: "Code sent" })
  requestCode(@CurrentUser() user: AuthenticatedUser): Promise<void> {
    return this.deletion.requestCode(user);
  }

  /** Checks the code (`400 invalid_code` / `code_expired` / `too_many_attempts`), then deletes the account. */
  @Post()
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiResponse({ status: 204, description: "Account deleted" })
  confirm(
    @CurrentUser() user: AuthenticatedUser,
    @Body() body: AccountDeletionRequestDto,
    @RequestId() requestId: string | undefined,
  ): Promise<void> {
    return this.deletion.deleteOwn(user, body.code, requestId);
  }
}
