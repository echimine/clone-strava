import {
  activitySummarySchema,
  paginatedResponseSchema,
  type ActivitySummary,
  type PaginatedResponse,
} from "@repo/contracts";
import { apiClient } from "@/lib/apiClient";

/**
 * Admin activities list (ADR-013, reference feature).
 *
 * `packages/contracts` does not expose a dedicated admin list contract yet
 * (only `activitySummarySchema`, from the mobile creation flow, ADR-019) and
 * `GET /v1/admin/activities` does not exist in `apps/api` yet either. This
 * follows the ADR-004 admin-role-guard convention and the schemas that do
 * exist so the feature's shape (hook → api.ts → apiClient, server-side
 * pagination) is ready once the endpoint and a richer contract land.
 */

const activityListResponseSchema = paginatedResponseSchema(activitySummarySchema);

export type ActivityListFilters = {
  page: number;
  limit: number;
};

export function listActivities(
  filters: ActivityListFilters,
  signal?: AbortSignal,
): Promise<PaginatedResponse<ActivitySummary>> {
  return apiClient("/v1/admin/activities", activityListResponseSchema, {
    searchParams: { page: filters.page, limit: filters.limit },
    signal,
  });
}

export function getActivity(id: string, signal?: AbortSignal): Promise<ActivitySummary> {
  return apiClient(`/v1/admin/activities/${id}`, activitySummarySchema, { signal });
}
