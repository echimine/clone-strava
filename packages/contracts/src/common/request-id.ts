import { z } from "zod";

/**
 * Correlation identifier (ADR-009 "Logs, in practice"): generated per HTTP
 * request, then copied into job payloads and published events so a single
 * activity can be followed from the API to the worker and then the WS
 * server.
 */
export const requestIdSchema = z.string().min(1);
export type RequestId = z.infer<typeof requestIdSchema>;

/** Optional `requestId` field shared by job payloads and domain/analytics events. */
export const requestIdFieldSchema = requestIdSchema.optional();
