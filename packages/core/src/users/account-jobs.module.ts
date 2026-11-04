import { BullModule } from "@nestjs/bullmq";
import { Module } from "@nestjs/common";
import { ACCOUNTS_QUEUE_NAME } from "@repo/contracts";
import { AccountJobs } from "./account-jobs.js";

/**
 * The `accounts` queue, owned by `users`, as a producer (ADR-038 §13). Kept apart from
 * `UsersModule` so the apps and specs that only read profiles need no `BullModule.forRoot`.
 */
@Module({
  imports: [BullModule.registerQueue({ name: ACCOUNTS_QUEUE_NAME })],
  providers: [AccountJobs],
  exports: [AccountJobs],
})
export class AccountJobsModule {}
