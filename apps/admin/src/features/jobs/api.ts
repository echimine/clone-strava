import {
  adminActivityRecomputeResponseSchema,
  adminActivityReprocessResponseSchema,
  adminBatchResponseSchema,
  adminFailedActivityListResponseSchema,
  adminFailedImportListResponseSchema,
  adminQueueJobDetailSchema,
  adminQueueJobListResponseSchema,
  adminQueueListResponseSchema,
  adminQueueRetryFailedResponseSchema,
  adminStaleActivityListResponseSchema,
  activityImportSchema,
  type AdminBatchResponse,
  type AdminFailedActivity,
  type AdminFailedActivityListResponse,
  type AdminFailedImport,
  type AdminFailedImportListResponse,
  type AdminStaleActivity,
  type AdminQueueJobDetail,
  type AdminQueueJobListResponse,
  type AdminQueueListResponse,
  type AdminQueueRetryFailedResponse,
  type AdminStaleActivityListResponse,
} from "@repo/contracts";
import { z } from "zod";
import { apiClient } from "@/lib/apiClient";

export type PageQuery = { page: number; pageSize: number };

/** A `204` has no body. */
const noContent = z.undefined();

// --- "Échecs" (ADR-038 §14) ---

export const failureLists = {
  activities: (query: PageQuery, signal?: AbortSignal): Promise<AdminFailedActivityListResponse> =>
    apiClient("/v1/admin/failures/activities", adminFailedActivityListResponseSchema, { searchParams: query, signal }),
  imports: (query: PageQuery, signal?: AbortSignal): Promise<AdminFailedImportListResponse> =>
    apiClient("/v1/admin/failures/imports", adminFailedImportListResponseSchema, { searchParams: query, signal }),
  recomputes: (query: PageQuery, signal?: AbortSignal): Promise<AdminStaleActivityListResponse> =>
    apiClient("/v1/admin/failures/recomputes", adminStaleActivityListResponseSchema, { searchParams: query, signal }),
};
export type FailureKind = keyof typeof failureLists;
/** The row of each "Échecs" list. */
export type FailureRows = {
  activities: AdminFailedActivity;
  imports: AdminFailedImport;
  recomputes: AdminStaleActivity;
};
export type FailurePage<Kind extends FailureKind> = {
  items: FailureRows[Kind][];
  total: number;
  page: number;
  pageSize: number;
};

export function listFailures<Kind extends FailureKind>(
  kind: Kind,
  query: PageQuery,
  signal?: AbortSignal,
): Promise<FailurePage<Kind>> {
  // `failureLists[kind]` answers the page of `FailureRows[kind]`, which TypeScript cannot follow.
  return failureLists[kind](query, signal) as Promise<FailurePage<Kind>>;
}

/** The unit domain action that relaunches one failure of each list. */
export const relaunchOne: Record<FailureKind, (id: string) => Promise<unknown>> = {
  activities: (id) =>
    apiClient(`/v1/admin/activities/${id}/reprocess`, adminActivityReprocessResponseSchema, { method: "POST" }),
  imports: (id) => apiClient(`/v1/admin/activity-imports/${id}/reprocess`, activityImportSchema, { method: "POST" }),
  recomputes: (id) =>
    apiClient(`/v1/admin/activities/${id}/recompute`, adminActivityRecomputeResponseSchema, { method: "POST" }),
};

/** « Retraiter les N en échec »: 500 at most per click; returns how many were relaunched. */
export const relaunchAll: Record<FailureKind, () => Promise<AdminBatchResponse>> = {
  activities: () => apiClient("/v1/admin/activities/reprocess-failed", adminBatchResponseSchema, { method: "POST" }),
  imports: () => apiClient("/v1/admin/activity-imports/reprocess-failed", adminBatchResponseSchema, { method: "POST" }),
  recomputes: () => apiClient("/v1/admin/activities/recompute-stale", adminBatchResponseSchema, { method: "POST" }),
};

// --- "Files" (ADR-038 §14) ---

export function listQueues(signal?: AbortSignal): Promise<AdminQueueListResponse> {
  return apiClient("/v1/admin/queues", adminQueueListResponseSchema, { signal });
}

export function listFailedJobs(queue: string, query: PageQuery, signal?: AbortSignal): Promise<AdminQueueJobListResponse> {
  return apiClient(`/v1/admin/queues/${queue}/jobs`, adminQueueJobListResponseSchema, {
    searchParams: { ...query, state: "failed" },
    signal,
  });
}

export function getJob(queue: string, id: string, signal?: AbortSignal): Promise<AdminQueueJobDetail> {
  return apiClient(`/v1/admin/queues/${queue}/jobs/${encodeURIComponent(id)}`, adminQueueJobDetailSchema, { signal });
}

export function retryJob(queue: string, id: string): Promise<void> {
  return apiClient(`/v1/admin/queues/${queue}/jobs/${encodeURIComponent(id)}/retry`, noContent, { method: "POST" });
}

export function retryFailedJobs(queue: string): Promise<AdminQueueRetryFailedResponse> {
  return apiClient(`/v1/admin/queues/${queue}/retry-failed`, adminQueueRetryFailedResponseSchema, { method: "POST" });
}

export function pauseQueue(queue: string): Promise<void> {
  return apiClient(`/v1/admin/queues/${queue}/pause`, noContent, { method: "POST" });
}

export function resumeQueue(queue: string): Promise<void> {
  return apiClient(`/v1/admin/queues/${queue}/resume`, noContent, { method: "POST" });
}
