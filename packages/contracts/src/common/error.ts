import { z } from "zod";

/**
 * Single API error format for the whole API (ADR-009 §7): a machine-readable
 * `code`, a human-readable `message`, and optional field-level `details` for
 * validation errors.
 */
export const apiErrorDetailSchema = z.object({
  field: z.string(),
  message: z.string(),
});
export type ApiErrorDetail = z.infer<typeof apiErrorDetailSchema>;

export const apiErrorSchema = z.object({
  code: z.string(),
  message: z.string(),
  details: z.array(apiErrorDetailSchema).optional(),
});
export type ApiError = z.infer<typeof apiErrorSchema>;

/** Envelope returned by every non-2xx API response. */
export const apiErrorResponseSchema = z.object({
  error: apiErrorSchema,
});
export type ApiErrorResponse = z.infer<typeof apiErrorResponseSchema>;
