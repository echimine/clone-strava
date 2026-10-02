import type { JobsOptions, Queue } from "bullmq";

/** Job states in which a job will still run: adding another would be a duplicate. */
const LIVE_JOB_STATES = new Set(["active", "waiting", "delayed", "prioritized", "waiting-children"]);

/** Retry policy for technical errors (ADR-019 §6, ADR-028 §7): 5 attempts, exponential from 30 s. */
export const DEFAULT_JOB_RETRY: JobsOptions = {
  attempts: 5,
  backoff: { type: "exponential", delay: 30_000 },
  removeOnComplete: { age: 24 * 3600 },
  removeOnFail: { age: 7 * 24 * 3600 },
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
