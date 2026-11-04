import { createZodDto } from "nestjs-zod";
import { adminBatchResponseSchema, type AdminBatchResponse } from "@repo/contracts";
import type { AuditDraft } from "../audit/audited.decorator.js";

/** What every « Retraiter les N en échec » answers (ADR-038 §14). */
export class AdminBatchResponseDto extends createZodDto(adminBatchResponseSchema) {}

/**
 * A batch's one Journal entry carries the count and the ids it relaunched (ADR-038 §14); the
 * response, the count.
 */
export function batched(audit: AuditDraft, ids: string[]): AdminBatchResponse {
  audit.details = { count: ids.length, ids };
  return { relaunched: ids.length };
}
