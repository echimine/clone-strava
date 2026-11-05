import { Inject, Injectable } from "@nestjs/common";
import { and, eq, isNotNull, sql } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import type { LonLat } from "@repo/geo";
import { DATABASE } from "../../infrastructure/index.js";

/** A Segment as the matching reads it (ADR-039 §6). */
export interface SegmentToMatch {
  id: string;
  sportTypeCode: string;
  createdBy: string | null;
  distanceM: number | null;
  path: LonLat[];
}

const pathGeoJson = sql<string>`ST_AsGeoJSON(${schema.segment.path})`;

function toSegmentToMatch(row: Omit<SegmentToMatch, "path"> & { path: string }): SegmentToMatch {
  const coordinates = (JSON.parse(row.path) as { coordinates: number[][] }).coordinates;
  return { ...row, path: coordinates.map(([lon, lat]) => ({ lat: lat!, lon: lon! })) };
}

const segmentToMatchColumns = {
  id: schema.segment.id,
  sportTypeCode: schema.segment.sportTypeCode,
  createdBy: schema.segment.createdBy,
  distanceM: schema.segment.distanceM,
  path: pathGeoJson,
};

/** Reads and writes on `segments.segment` only (ADR-021 §6). */
@Injectable()
export class SegmentRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  /**
   * Prefilter of `match-segments` (ADR-039 §6): the Segments of a sport whose start and end lie
   * within `marginDeg` of the trace (EWKT, a parameter never stored), through the GiST indexes on
   * `start_point` and `end_point`. The exact test is `matchSegment`'s, in meters.
   */
  async findNearTrace(sportTypeCode: string, traceEwkt: string, marginDeg: number): Promise<SegmentToMatch[]> {
    const trace = sql`ST_GeomFromEWKT(${traceEwkt})`;
    const rows = await this.db
      .select(segmentToMatchColumns)
      .from(schema.segment)
      .where(
        and(
          eq(schema.segment.sportTypeCode, sportTypeCode),
          isNotNull(schema.segment.path),
          sql`ST_DWithin(${schema.segment.startPoint}, ${trace}, ${marginDeg})`,
          sql`ST_DWithin(${schema.segment.endPoint}, ${trace}, ${marginDeg})`,
        ),
      );
    return rows.map(toSegmentToMatch);
  }

  /** The Segment of a retro-matching page, `undefined` once deleted or without a path. */
  async findById(id: string): Promise<(SegmentToMatch & { start: LonLat; end: LonLat }) | undefined> {
    const [row] = await this.db
      .select(segmentToMatchColumns)
      .from(schema.segment)
      .where(and(eq(schema.segment.id, id), isNotNull(schema.segment.path)));
    if (!row) {
      return undefined;
    }
    const segment = toSegmentToMatch(row);
    return { ...segment, start: segment.path[0]!, end: segment.path.at(-1)! };
  }

  /** ADR-039 §7: the last retro-matching page is done. */
  async markHistoryMatched(id: string): Promise<void> {
    await this.db
      .update(schema.segment)
      .set({ historyMatchedAt: sql`now()` })
      .where(eq(schema.segment.id, id));
  }
}
