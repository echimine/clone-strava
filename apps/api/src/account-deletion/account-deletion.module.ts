import { Module } from "@nestjs/common";
import { AuditModule } from "@repo/core/audit";
import { ModerationModule } from "@repo/core/moderation";
import { EmailJobsModule } from "@repo/core/notifications";
import { AccountJobsModule, UsersModule } from "@repo/core/users";
import { AuthModule } from "../auth/auth.module.js";
import { AccountDeletion } from "./account-deletion.js";

/**
 * The account deletion service (ADR-038 §13), composed in the API because it crosses layer-0
 * modules (`auth`, `moderation`, `audit`, `users`) that may not call each other. Used by
 * `/v1/me/account-deletion*` and `DELETE /v1/admin/users/:id`.
 */
@Module({
  imports: [AuthModule, AuditModule, ModerationModule, UsersModule, EmailJobsModule, AccountJobsModule],
  providers: [AccountDeletion],
  exports: [AccountDeletion],
})
export class AccountDeletionModule {}
