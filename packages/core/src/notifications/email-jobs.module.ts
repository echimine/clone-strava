import { BullModule } from "@nestjs/bullmq";
import { Module } from "@nestjs/common";
import { EMAILS_QUEUE_NAME } from "@repo/contracts";
import { EmailJobs } from "./email-jobs.js";

/**
 * The `emails` queue as a producer (ADR-038 §4): import it wherever an e-mail is enqueued (api,
 * worker, a domain module). The app must register `BullModule.forRoot`.
 */
@Module({
  imports: [BullModule.registerQueue({ name: EMAILS_QUEUE_NAME })],
  providers: [EmailJobs],
  exports: [EmailJobs],
})
export class EmailJobsModule {}
