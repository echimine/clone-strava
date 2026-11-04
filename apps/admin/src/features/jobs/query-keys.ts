import type { FailureKind, PageQuery } from "@/features/jobs/api";

/** Hierarchical cache keys of the `jobs` feature (TanStack Query query-keys guide). */
export const jobKeys = {
  all: ["jobs"] as const,
  failures: () => [...jobKeys.all, "failures"] as const,
  failureList: (kind: FailureKind, query: PageQuery) => [...jobKeys.failures(), kind, query] as const,
  queues: () => [...jobKeys.all, "queues"] as const,
  queueJobs: (queue: string, query: PageQuery) => [...jobKeys.queues(), queue, "jobs", query] as const,
  job: (queue: string, id: string) => [...jobKeys.queues(), queue, "job", id] as const,
};

/**
 * Caches other features own (which this feature may not import): every relaunch changes the
 * Activities, and every action adds a Journal entry.
 */
export const activitiesKey = ["activities"] as const;
export const journalKey = ["audit"] as const;
