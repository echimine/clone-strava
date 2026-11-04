import type { JobsOptions, Queue } from "bullmq";

/** Job states in which a job will still run: adding another would be a duplicate. */
const LIVE_JOB_STATES = new Set(["active", "waiting", "delayed", "prioritized", "waiting-children"]);

const DAY_S = 24 * 3600;

/**
 * How long Redis keeps finished jobs (ADR-038 §14, amends ADR-011), for every job, the job
 * schedulers' templates included: completed ones 7 days and 1000 at most, failed ones 30 days
 * and 5000 at most. The durable history stays in the database.
 */
export const JOB_RETENTION = {
  removeOnComplete: { age: 7 * DAY_S, count: 1000 },
  removeOnFail: { age: 30 * DAY_S, count: 5000 },
} as const satisfies JobsOptions;

/**
 * Retry policy for technical errors (ADR-019 §6, ADR-028 §7): 5 attempts, exponential from 30 s,
 * kept in Redis as long as {@link JOB_RETENTION} says.
 */
export const DEFAULT_JOB_RETRY: JobsOptions = {
  attempts: 5,
  backoff: { type: "exponential", delay: 30_000 },
  ...JOB_RETENTION,
};

/**
 * Adds a job under its deterministic jobId (ADR-011 §2). BullMQ silently
 * ignores an `add` whose jobId is still stored, even when that job is
 * finished, so a finished job holding the id is removed first
 * (reconciliation, reprocessing). Returns `false` when a live job
 * already exists.
 */
export async function enqueueUnique<T>(
  queue: Queue<T>,
  name: string,
  data: T,
  jobId: string,
  options: JobsOptions = DEFAULT_JOB_RETRY,
): Promise<boolean> {
  const existing = await queue.getJob(jobId);
  if (existing) {
    if (LIVE_JOB_STATES.has(await existing.getState())) {
      return false;
    }
    await existing.remove();
  }
  // `Queue<T>`'s generic name/data typing is stricter than needed here.
  await (queue as Queue).add(name, data, { ...options, jobId });
  return true;
}
