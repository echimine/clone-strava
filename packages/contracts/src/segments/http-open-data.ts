import { z } from "zod";

/**
 * The weekly ODbL file of every Segment (ADR-039 §10): its key in the bucket, and its route under
 * `/v1` (`GET /v1/open-data/segments.ndjson.gz`, public, unauthenticated, ADR-039 §12).
 */
export const OPEN_DATA_SEGMENTS_KEY = "open-data/segments.ndjson.gz";

/** `export-segments-odbl` (ADR-039 §13): weekly, on the `segments` queue. */
export const EXPORT_SEGMENTS_ODBL_JOB_NAME = "export-segments-odbl";

/** First line of the file: the licence and the attributions it travels with (ODbL §4.3, §4.6). */
export const openDataSegmentsHeaderSchema = z.object({
  type: z.literal("Metadata"),
  license: z.literal("ODbL-1.0"),
  licenseUrl: z.string(),
  attribution: z.array(z.string()),
  generatedAt: z.iso.datetime(),
});
export type OpenDataSegmentsHeader = z.infer<typeof openDataSegmentsHeaderSchema>;

/**
 * Every following line: one Segment as a GeoJSON Feature, a LineString with altitudes. No
 * creator, no provenance, no Effort (ADR-039 §10).
 */
export const openDataSegmentFeatureSchema = z.object({
  type: z.literal("Feature"),
  id: z.uuid(),
  geometry: z.object({
    type: z.literal("LineString"),
    coordinates: z.array(z.tuple([z.number(), z.number(), z.number()])),
  }),
  properties: z.object({
    name: z.string(),
    sport: z.string(),
    distanceM: z.number().nullable(),
    elevationGainM: z.number().nullable(),
    avgGrade: z.number().nullable(),
    maxGrade: z.number().nullable(),
    climbCategory: z.enum(["hc", "1", "2", "3", "4"]).nullable(),
  }),
});
export type OpenDataSegmentFeature = z.infer<typeof openDataSegmentFeatureSchema>;
