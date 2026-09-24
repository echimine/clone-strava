import { meResponseSchema, type MeResponse } from "@repo/contracts";
import { apiClient } from "@/lib/apiClient";

/** `GET /v1/me`: current user, role and premium status (ADR-013). */
export function getMe(signal?: AbortSignal): Promise<MeResponse> {
  return apiClient("/v1/me", meResponseSchema, { signal });
}
