import { Processor, WorkerHost } from "@nestjs/bullmq";
import { Logger } from "@nestjs/common";
import { UnrecoverableError, type Job } from "bullmq";
import {
  ACCOUNTS_QUEUE_NAME,
  DELETE_ACCOUNT_JOB_NAME,
  deleteAccountJobSchema,
  userActivitiesPrefix,
  userAvatarsPrefix,
  userImportsPrefix,
} from "@repo/contracts";
import { AuditService } from "@repo/core/audit";
import { StorageService } from "@repo/core/storage";
import { SubscriptionsService } from "@repo/core/subscriptions";
import { PostHogPersons } from "./posthog-persons.js";

/**
 * The `delete-account` job (ADR-038 §13), once the account is gone from the database: its three
 * bucket prefixes (ADR-037 §11), then its RevenueCat customer, then its PostHog person **last**,
 * then the Journal entry `user.delete.complete`, author « Système ». Every step tolerates « already
 * gone », so a retry replays the whole job safely; a step without its keys is skipped and logged.
 */
@Processor(ACCOUNTS_QUEUE_NAME, { concurrency: 2 })
export class DeleteAccountProcessor extends WorkerHost {
  private readonly logger = new Logger(DeleteAccountProcessor.name);

  constructor(
    private readonly storage: StorageService,
    private readonly subscriptions: SubscriptionsService,
    private readonly postHogPersons: PostHogPersons,
    private readonly audit: AuditService,
  ) {
    super();
  }

  async process(job: Job): Promise<void> {
    if (job.name !== DELETE_ACCOUNT_JOB_NAME) {
      this.logger.warn(`Unknown job name on queue "${ACCOUNTS_QUEUE_NAME}": ${job.name}`);
      return;
    }
    const parsed = deleteAccountJobSchema.safeParse(job.data);
    if (!parsed.success) {
      throw new UnrecoverableError(`Invalid ${DELETE_ACCOUNT_JOB_NAME} payload`);
    }
    const { userId, requestId } = parsed.data;

    for (const prefix of [userActivitiesPrefix(userId), userImportsPrefix(userId), userAvatarsPrefix(userId)]) {
      await this.storage.deleteFolder(prefix);
    }
    const revenueCat = await this.subscriptions.deleteRevenueCatCustomer(userId);
    const postHog = await this.postHogPersons.delete(userId);
    for (const [step, outcome] of [
      ["RevenueCat", revenueCat],
      ["PostHog", postHog],
    ] as const) {
      if (outcome === "skipped") {
        this.logger.warn({ userId }, `${step} not configured: the deleted account's ${step} data is left`);
      }
    }

    await this.audit.record({
      actorId: null,
      action: "user.delete.complete",
      targetId: userId,
      subjectUserId: userId,
      details: { bucket: "deleted", revenueCat, postHog },
      requestId: requestId ?? null,
    });
    this.logger.log({ userId, revenueCat, postHog }, "Deleted account cleaned up");
  }
}
