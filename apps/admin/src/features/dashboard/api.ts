import {
  adminGrowthStatsSchema,
  adminTodoStatsSchema,
  type AdminGrowthStats,
  type AdminStatsPeriod,
  type AdminTodoStats,
} from "@repo/contracts";
import { apiClient } from "@/lib/apiClient";

/** `GET /v1/admin/stats/todo` (ADR-038 §15): the work waiting now. */
export function getTodoStats(signal?: AbortSignal): Promise<AdminTodoStats> {
  return apiClient("/v1/admin/stats/todo", adminTodoStatsSchema, { signal });
}

/** `GET /v1/admin/stats/growth?period=` (ADR-038 §15): the period against the previous one. */
export function getGrowthStats(period: AdminStatsPeriod, signal?: AbortSignal): Promise<AdminGrowthStats> {
  return apiClient("/v1/admin/stats/growth", adminGrowthStatsSchema, { searchParams: { period }, signal });
}
