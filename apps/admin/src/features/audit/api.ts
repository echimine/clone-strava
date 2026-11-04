import {
  auditActorListResponseSchema,
  auditEntryListResponseSchema,
  type AuditAction,
  type AuditActorListResponse,
  type AuditEntryListResponse,
} from "@repo/contracts";
import { apiClient } from "@/lib/apiClient";

/** Filters of `GET /v1/admin/audit-entries` (ADR-038 §3); `from`/`to` are Paris days. */
export type AuditEntryFilters = {
  page: number;
  pageSize: number;
  actorId?: string;
  action?: AuditAction;
  subjectUserId?: string;
  from?: string;
  to?: string;
};

export function listAuditEntries(filters: AuditEntryFilters, signal?: AbortSignal): Promise<AuditEntryListResponse> {
  return apiClient("/v1/admin/audit-entries", auditEntryListResponseSchema, { searchParams: filters, signal });
}

export function listAuditActors(signal?: AbortSignal): Promise<AuditActorListResponse> {
  return apiClient("/v1/admin/audit-entries/actors", auditActorListResponseSchema, { signal });
}
