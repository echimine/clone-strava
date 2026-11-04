import {
  adminActivityTextResponseSchema,
  adminReportCaseCloseResponseSchema,
  adminReportCaseDetailSchema,
  adminReportCaseListResponseSchema,
  type AdminReportCaseCloseResponse,
  type AdminReportCaseDetail,
  type AdminReportCaseListResponse,
  type AdminReportCaseState,
  type BanDuration,
  type ReportReason,
  type ReportTargetType,
} from "@repo/contracts";
import { z } from "zod";
import { apiClient } from "@/lib/apiClient";

/** Filters of `GET /v1/admin/reports` (ADR-038 §10); `from`/`to` are Paris days of the opening. */
export type ReportCaseListFilters = {
  page: number;
  pageSize: number;
  state: AdminReportCaseState;
  targetType?: ReportTargetType;
  reason?: ReportReason;
  from?: string;
  to?: string;
};

/** A `204` has no body. */
const noContent = z.undefined();

export function listReportCases(
  filters: ReportCaseListFilters,
  signal?: AbortSignal,
): Promise<AdminReportCaseListResponse> {
  return apiClient("/v1/admin/reports", adminReportCaseListResponseSchema, { searchParams: filters, signal });
}

export function getReportCase(caseId: string, signal?: AbortSignal): Promise<AdminReportCaseDetail> {
  return apiClient(`/v1/admin/reports/${caseId}`, adminReportCaseDetailSchema, { signal });
}

/** « Clore » as « Sanctionné » (`resolve`) or « Rejeter » (`dismiss`), with an optional note. */
export function closeReportCase(
  caseId: string,
  outcome: "resolve" | "dismiss",
  note: string,
): Promise<AdminReportCaseCloseResponse> {
  return apiClient(`/v1/admin/reports/${caseId}/${outcome}`, adminReportCaseCloseResponseSchema, {
    method: "POST",
    body: note ? { note } : {},
  });
}

// --- The Sanctions a case offers (ADR-038 §10): the endpoints of the Activities and users areas. ---

export function removeComment(commentId: string, reason: string): Promise<void> {
  return apiClient(`/v1/admin/comments/${commentId}`, noContent, { method: "DELETE", body: { reason } });
}

export function deleteActivity(activityId: string, reason: string): Promise<void> {
  return apiClient(`/v1/admin/activities/${activityId}`, noContent, { method: "DELETE", body: { reason } });
}

export function removeMedia(activityId: string, mediaId: string, reason: string): Promise<void> {
  return apiClient(`/v1/admin/activities/${activityId}/media/${mediaId}`, noContent, {
    method: "DELETE",
    body: { reason },
  });
}

export async function resetActivityText(activityId: string, reason: string): Promise<void> {
  await apiClient(`/v1/admin/activities/${activityId}/reset-text`, adminActivityTextResponseSchema, {
    method: "POST",
    body: { reason },
  });
}

export type ProfileReset = "reset-name" | "reset-bio" | "reset-avatar";

export function resetProfile(userId: string, reset: ProfileReset, reason: string): Promise<void> {
  return apiClient(`/v1/admin/users/${userId}/${reset}`, noContent, { method: "POST", body: { reason } });
}

export function banUser(userId: string, duration: BanDuration, reason: string): Promise<void> {
  return apiClient(`/v1/admin/users/${userId}/ban`, noContent, { method: "POST", body: { duration, reason } });
}
