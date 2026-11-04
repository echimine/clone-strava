import {
  adminUserDetailSchema,
  adminUserListResponseSchema,
  adminUserReportsResponseSchema,
  adminUserSessionsResponseSchema,
  type AdminUserDetail,
  type AdminUserListResponse,
  type AdminUserReportsResponse,
  type AdminUserSessionsResponse,
  type BanDuration,
  type UserRole,
} from "@repo/contracts";
import { z } from "zod";
import { apiClient } from "@/lib/apiClient";

/** Filters of `GET /v1/admin/users` (ADR-038 §5); `from`/`to` are Paris days of the sign-up. */
export type UserListFilters = {
  page: number;
  pageSize: number;
  q?: string;
  role?: UserRole;
  state?: "active" | "banned" | "temporarily_banned";
  premium?: "yes" | "no";
  method?: "email_code" | "google";
  from?: string;
  to?: string;
  sort?: "createdAt" | "lastActivityAt";
  order?: "asc" | "desc";
};

/** A `204` has no body. */
const noContent = z.undefined();

export function listUsers(filters: UserListFilters, signal?: AbortSignal): Promise<AdminUserListResponse> {
  return apiClient("/v1/admin/users", adminUserListResponseSchema, { searchParams: filters, signal });
}

export function getUser(id: string, signal?: AbortSignal): Promise<AdminUserDetail> {
  return apiClient(`/v1/admin/users/${id}`, adminUserDetailSchema, { signal });
}

export function getUserSessions(id: string, signal?: AbortSignal): Promise<AdminUserSessionsResponse> {
  return apiClient(`/v1/admin/users/${id}/sessions`, adminUserSessionsResponseSchema, { signal });
}

export function getUserReports(id: string, signal?: AbortSignal): Promise<AdminUserReportsResponse> {
  return apiClient(`/v1/admin/users/${id}/reports`, adminUserReportsResponseSchema, { signal });
}

// --- Sanctions (ADR-038 §4): each takes the reason the athlete will read. ---

export function banUser(id: string, duration: BanDuration, reason: string): Promise<void> {
  return apiClient(`/v1/admin/users/${id}/ban`, noContent, { method: "POST", body: { duration, reason } });
}

export function unbanUser(id: string, reason: string): Promise<void> {
  return apiClient(`/v1/admin/users/${id}/unban`, noContent, { method: "POST", body: { reason } });
}

export function signOutUser(id: string, reason: string): Promise<void> {
  return apiClient(`/v1/admin/users/${id}/sign-out`, noContent, { method: "POST", body: { reason } });
}

export type ProfileReset = "reset-name" | "reset-bio" | "reset-avatar";

export function resetProfile(id: string, reset: ProfileReset, reason: string): Promise<void> {
  return apiClient(`/v1/admin/users/${id}/${reset}`, noContent, { method: "POST", body: { reason } });
}

/** Not a Sanction: optional reason. */
export function setUserRole(id: string, role: UserRole, reason: string): Promise<void> {
  return apiClient(`/v1/admin/users/${id}/role`, noContent, {
    method: "PUT",
    body: reason ? { role, reason } : { role },
  });
}
