import { getQueueToken } from "@nestjs/bullmq";
import { ConflictException, Injectable, NotFoundException } from "@nestjs/common";
import { ModuleRef } from "@nestjs/core";
import type { Job, JobSchedulerJson, Queue } from "bullmq";
import {
  ADMIN_QUEUE_NAMES,
  ADMIN_RETRY_REFUSED_JOB_NAMES,
  type AdminQueue,
  type AdminQueueJob,
  type AdminQueueJobDetail,
  type AdminQueueJobListQuery,
  type AdminQueueJobListResponse,
  type AdminQueueName,
  type AdminQueueRetryFailedResponse,
  type AdminQueueScheduler,
} from "@repo/contracts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Reads and drives the whitelisted BullMQ queues for the backoffice (ADR-038 §14), as a
 * producer only: counts, pause state, schedulers, jobs by state; retry a failed job (attempts
 * reset), retry every failure of a queue, pause, resume. Nothing here removes a job: no
 * `remove`, `drain`, `clean` nor `obliterate`. A queue no job has used yet reads as empty.
 *
 * `process-activity` and `import-activity` are never retried raw: they do nothing unless their
 * Activity or import is `processing`; « Retraiter » (`Échecs` tab) relaunches them.
 */
@Injectable()
export class AdminQueues {
  constructor(private readonly moduleRef: ModuleRef) {}

  /** Every whitelisted queue, in the whitelist's order. */
  list(): Promise<AdminQueue[]> {
    return Promise.all(ADMIN_QUEUE_NAMES.map((name) => this.describe(name)));
  }

  async jobs(name: string, query: AdminQueueJobListQuery): Promise<AdminQueueJobListResponse> {
    const queue = this.queue(name);
    const start = (query.page - 1) * query.pageSize;
    const [jobs, total] = await Promise.all([
      // Newest first.
      queue.getJobs([query.state], start, start + query.pageSize - 1, false),
      queue.getJobCountByTypes(query.state),
    ]);
    return {
      items: jobs.filter((job): job is Job => Boolean(job)).map((job) => toJob(job, queue.name as AdminQueueName)),
      total,
      page: query.page,
      pageSize: query.pageSize,
    };
  }

  async job(name: string, id: string): Promise<AdminQueueJobDetail> {
    const queue = this.queue(name);
    const job = await this.findJob(queue, id);
    const data: unknown = job.data;
    return {
      ...toJob(job, queue.name as AdminQueueName),
      state: await job.getState(),
      stacktrace: job.stacktrace ?? [],
      data,
      activityId: uuidField(data, "activityId"),
      userId: uuidField(data, "userId"),
    };
  }

  /** `409 retry_refused` for a job « Retraiter » relaunches, `409 not_failed` unless failed. */
  async retry(name: string, id: string): Promise<void> {
    const job = await this.findJob(this.queue(name), id);
    if (isRetryRefused(job)) {
      throw new ConflictException({
        code: "retry_refused",
        message: `A raw retry of ${job.name} does nothing: use « Retraiter » in the Échecs tab`,
      });
    }
    if ((await job.getState()) !== "failed") {
      throw new ConflictException({ code: "not_failed", message: "Only failed jobs can be retried" });
    }
    await job.retry("failed", { resetAttemptsMade: true });
  }

  /** Retries every failed job of the queue (at most the 5000 kept), but the refused ones. */
  async retryFailed(name: string): Promise<AdminQueueRetryFailedResponse> {
    const failed = (await this.queue(name).getJobs(["failed"], 0, -1)).filter((job): job is Job => Boolean(job));
    let retried = 0;
    let refused = 0;
    for (const job of failed) {
      if (isRetryRefused(job)) {
        refused++;
        continue;
      }
      await job.retry("failed", { resetAttemptsMade: true });
      retried++;
    }
    return { retried, refused };
  }

  async pause(name: string): Promise<void> {
    await this.queue(name).pause();
  }

  async resume(name: string): Promise<void> {
    await this.queue(name).resume();
  }

  /** `404 queue_not_found` outside the whitelist. */
  queue(name: string): Queue {
    if (!(ADMIN_QUEUE_NAMES as readonly string[]).includes(name)) {
      throw new NotFoundException({ code: "queue_not_found", message: `No queue named ${name}` });
    }
    return this.moduleRef.get<Queue>(getQueueToken(name), { strict: false });
  }

  private async describe(name: AdminQueueName): Promise<AdminQueue> {
    const queue = this.queue(name);
    const [counts, isPaused, schedulers] = await Promise.all([
      queue.getJobCounts("waiting", "active", "delayed", "prioritized", "waiting-children", "completed", "failed"),
      queue.isPaused(),
      queue.getJobSchedulers(),
    ]);
    return {
      name,
      isPaused,
      counts: {
        waiting: counts.waiting ?? 0,
        active: counts.active ?? 0,
        delayed: counts.delayed ?? 0,
        prioritized: counts.prioritized ?? 0,
        waitingChildren: counts["waiting-children"] ?? 0,
        completed: counts.completed ?? 0,
        failed: counts.failed ?? 0,
      },
      schedulers: schedulers.map(toScheduler),
    };
  }

  private async findJob(queue: Queue, id: string): Promise<Job> {
    const job = await queue.getJob(id);
    if (!job) {
      throw new NotFoundException({ code: "job_not_found", message: `No job ${id} in ${queue.name}` });
    }
    return job;
  }
}

function isRetryRefused(job: Job): boolean {
  return ADMIN_RETRY_REFUSED_JOB_NAMES.includes(job.name);
}

function toJob(job: Job, queue: AdminQueueName): AdminQueueJob {
  return {
    id: job.id ?? "",
    name: job.name,
    queue,
    failedReason: job.failedReason || null,
    attemptsMade: job.attemptsMade,
    maxAttempts: Math.max(job.opts.attempts ?? 1, 1),
    createdAt: new Date(job.timestamp).toISOString(),
    processedAt: job.processedOn ? new Date(job.processedOn).toISOString() : null,
    finishedAt: job.finishedOn ? new Date(job.finishedOn).toISOString() : null,
    retryRefused: isRetryRefused(job),
  };
}

function toScheduler(scheduler: JobSchedulerJson): AdminQueueScheduler {
  return {
    id: scheduler.id ?? scheduler.key,
    jobName: scheduler.name,
    everyMs: scheduler.every ?? null,
    pattern: scheduler.pattern ?? null,
    timeZone: scheduler.tz ?? null,
    nextRunAt: scheduler.next ? new Date(scheduler.next).toISOString() : null,
  };
}

/** `data[field]` when it is a uuid, for the links of a job's detail. */
function uuidField(data: unknown, field: string): string | null {
  if (typeof data !== "object" || data === null) {
    return null;
  }
  const value = (data as Record<string, unknown>)[field];
  return typeof value === "string" && UUID.test(value) ? value : null;
}
