import { Processor, WorkerHost } from "@nestjs/bullmq";
import { Inject, Logger } from "@nestjs/common";
import { UnrecoverableError, type Job } from "bullmq";
import { EMAILS_QUEUE_NAME, SEND_EMAIL_JOB_NAME, sendEmailJobSchema } from "@repo/contracts";
import { NotificationsService, emailWordmarkUrl, renderEmailJob } from "@repo/core/notifications";
import { EMAILS_PROCESSOR_OPTIONS, type EmailsProcessorOptions } from "./emails.constants.js";

/**
 * The `send-email` job (ADR-038 §4): renders its template with what the job carries and sends it
 * through `notifications`, the team's address as Reply-To. A refused send is retried under the
 * same idempotency key, so Resend never sends it twice; an invalid payload fails for good.
 */
@Processor(EMAILS_QUEUE_NAME, { concurrency: 5 })
export class SendEmailProcessor extends WorkerHost {
  private readonly logger = new Logger(SendEmailProcessor.name);
  private readonly logoUrl: string;
  private readonly contactEmail: string | null;

  constructor(
    private readonly notifications: NotificationsService,
    @Inject(EMAILS_PROCESSOR_OPTIONS) options: EmailsProcessorOptions,
  ) {
    super();
    this.logoUrl = emailWordmarkUrl(options.adminOrigin);
    this.contactEmail = options.contactEmail ?? null;
  }

  async process(job: Job): Promise<void> {
    if (job.name !== SEND_EMAIL_JOB_NAME) {
      this.logger.warn(`Unknown job name on queue "${EMAILS_QUEUE_NAME}": ${job.name}`);
      return;
    }
    const parsed = sendEmailJobSchema.safeParse(job.data);
    if (!parsed.success) {
      throw new UnrecoverableError(`Invalid ${SEND_EMAIL_JOB_NAME} payload`);
    }
    const email = parsed.data;
    const { subject, html } = await renderEmailJob(email, { logoUrl: this.logoUrl, contactEmail: this.contactEmail });
    const result = await this.notifications.sendEmail({
      to: email.to,
      subject,
      html,
      idempotencyKey: email.idempotencyKey,
      ...(this.contactEmail ? { replyTo: this.contactEmail } : {}),
    });
    if (!result.sent) {
      throw new Error(`E-mail ${email.template} not sent: ${result.error}`);
    }
    this.logger.log({ template: email.template, idempotencyKey: email.idempotencyKey }, "E-mail sent");
  }
}
