import {
  adminActivityDetailSchema,
  adminActivityListResponseSchema,
  adminActivityReprocessResponseSchema,
  adminActivityTextResponseSchema,
  type ActivitySource,
  type AdminActivityDetail,
  type AdminActivityListResponse,
  type AdminActivityReprocessResponse,
  type AdminActivityTextResponse,
  type ProcessingStatus,
  type Visibility,
} from "@repo/contracts";
import { z } from "zod";
import { apiClient } from "@/lib/apiClient";

/** Filters of `GET /v1/admin/activities` (ADR-038 §11); `from`/`to` are Paris days of the start. */
export type ActivityListFilters = {
  page: number;
  pageSize: number;
  q?: string;
  status?: ProcessingStatus;
  source?: ActivitySource;
  sportTypeCode?: string;
  visibility?: Visibility;
  userId?: string;
  from?: string;
  to?: string;
};

/** A `204` has no body. */
const noContent = z.undefined();

export function listActivities(filters: ActivityListFilters, signal?: AbortSignal): Promise<AdminActivityListResponse> {
  return apiClient("/v1/admin/activities", adminActivityListResponseSchema, { searchParams: filters, signal });
}

export function getActivity(id: string, signal?: AbortSignal): Promise<AdminActivityDetail> {
  return apiClient(`/v1/admin/activities/${id}`, adminActivityDetailSchema, { signal });
}

/** « Retraiter » a failed Activity (not a Sanction). */
export function reprocessActivity(id: string): Promise<AdminActivityReprocessResponse> {
  return apiClient(`/v1/admin/activities/${id}/reprocess`, adminActivityReprocessResponseSchema, { method: "POST" });
}

// --- Sanctions (ADR-038 §4): each takes the reason the athlete will read. ---

export function deleteActivity(id: string, reason: string): Promise<void> {
  return apiClient(`/v1/admin/activities/${id}`, noContent, { method: "DELETE", body: { reason } });
}

export function removeMedia(activityId: string, mediaId: string, reason: string): Promise<void> {
  return apiClient(`/v1/admin/activities/${activityId}/media/${mediaId}`, noContent, {
    method: "DELETE",
    body: { reason },
  });
}

export function resetActivityText(id: string, reason: string): Promise<AdminActivityTextResponse> {
  return apiClient(`/v1/admin/activities/${id}/reset-text`, adminActivityTextResponseSchema, {
    method: "POST",
    body: { reason },
  });
}

export function removeComment(commentId: string, reason: string): Promise<void> {
  return apiClient(`/v1/admin/comments/${commentId}`, noContent, { method: "DELETE", body: { reason } });
}
