import { InjectQueue } from "@nestjs/bullmq";
import { Injectable } from "@nestjs/common";
import type { Queue } from "bullmq";
import {
  ACCOUNTS_QUEUE_NAME,
  DELETE_ACCOUNT_JOB_NAME,
  deleteAccountJobId,
  deleteAccountJobSchema,
  type DeleteAccountJob,
} from "@repo/contracts";
import { DEFAULT_JOB_RETRY, enqueueUnique } from "../infrastructure/index.js";

/**
 * Puts the cleanup of a deleted account in the `accounts` queue (ADR-038 §13): bucket,
 * RevenueCat, PostHog, then the Journal, run by `apps/worker`. One job per account, retried.
 */
@Injectable()
export class AccountJobs {
  constructor(@InjectQueue(ACCOUNTS_QUEUE_NAME) private readonly queue: Queue<DeleteAccountJob>) {}

  /** `false` when the cleanup of this account is already waiting or running. */
  enqueueDeletion(job: DeleteAccountJob): Promise<boolean> {
    const data = deleteAccountJobSchema.parse(job);
    return enqueueUnique(this.queue, DELETE_ACCOUNT_JOB_NAME, data, deleteAccountJobId(data.userId), DEFAULT_JOB_RETRY);
  }
}
