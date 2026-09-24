import { z } from "zod";
import { requestIdFieldSchema } from "../common/request-id.js";

/**
 * Emitted after `match-segments` (ADR-019 §8), forwarded by the realtime
 * bridge as `activity.segments_matched` (ADR-021 §5).
 */
export const SEGMENTS_EFFORTS_MATCHED_EVENT = "segments.efforts.matched";

export const segmentsEffortsMatchedEventSchema = z.object({
  activityId: z.uuid(),
  userId: z.uuid(),
  requestId: requestIdFieldSchema,
});
export type SegmentsEffortsMatchedEvent = z.infer<typeof segmentsEffortsMatchedEventSchema>;
