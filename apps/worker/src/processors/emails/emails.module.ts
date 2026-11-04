import { BullModule } from "@nestjs/bullmq";
import { type DynamicModule, Module } from "@nestjs/common";
import { EMAILS_QUEUE_NAME } from "@repo/contracts";
import { NotificationsModule } from "@repo/core/notifications";
import { EMAILS_PROCESSOR_OPTIONS, type EmailsProcessorOptions } from "./emails.constants.js";
import { SendEmailProcessor } from "./send-email.processor.js";

/** The `emails` queue (ADR-038 §4): renders and sends the e-mails enqueued by `EmailJobs`. */
@Module({})
export class EmailsProcessorModule {
  static forRoot(options: EmailsProcessorOptions): DynamicModule {
    return {
      module: EmailsProcessorModule,
      imports: [
        NotificationsModule.forRoot({ apiKey: options.resendApiKey }),
        BullModule.registerQueue({ name: EMAILS_QUEUE_NAME }),
      ],
      providers: [{ provide: EMAILS_PROCESSOR_OPTIONS, useValue: options }, SendEmailProcessor],
    };
  }
}
