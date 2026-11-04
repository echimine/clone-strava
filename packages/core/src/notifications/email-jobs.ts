import { InjectQueue } from "@nestjs/bullmq";
import { Injectable } from "@nestjs/common";
import type { Queue } from "bullmq";
import {
  EMAILS_QUEUE_NAME,
  SEND_EMAIL_JOB_NAME,
  sendEmailJobId,
  sendEmailJobSchema,
  type SendEmailJob,
} from "@repo/contracts";
import { DEFAULT_JOB_RETRY } from "../infrastructure/index.js";

/**
 * Puts e-mails in the `emails` queue (ADR-038 §4): the one way to send an e-mail after the fact
 * (Sanction e-mails, account deleted, new report case for the Administrators). Call it once the
 * action has succeeded, with everything the template names, since the content or the account
 * may be gone when the worker runs. One job per `idempotencyKey`: enqueuing the same key again
 * while its job is stored does nothing, and Resend never sends a key twice.
 */
@Injectable()
export class EmailJobs {
  constructor(@InjectQueue(EMAILS_QUEUE_NAME) private readonly queue: Queue) {}

  /** Validates `job` against its template's contract, then enqueues it; throws on bad data. */
  async enqueue(job: SendEmailJob): Promise<void> {
    const data = sendEmailJobSchema.parse(job);
    await this.queue.add(SEND_EMAIL_JOB_NAME, data, { ...DEFAULT_JOB_RETRY, jobId: sendEmailJobId(data.idempotencyKey) });
  }
}
