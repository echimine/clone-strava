import { Inject, Injectable } from "@nestjs/common";
import { and, eq, inArray, isNotNull, sql } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import type { LonLat } from "@repo/geo";
import { DATABASE, type DbExecutor } from "../../infrastructure/index.js";
import type { ClimbCategory } from "../domain/climb-category.js";

/** A line of the Nervo generator, ready to insert (ADR-039 §10). */
export interface NervoSegmentToInsert {
  sourceKey: string;
  sportTypeCode: string;
  name: string;
  /** `[lon, lat, altitude]`. */
  path: ReadonlyArray<readonly [number, number, number]>;
  distanceM: number;
  avgGrade: number;
  maxGrade: number;
  elevationGainM: number;
  minAltitudeM: number;
  maxAltitudeM: number;
  climbCategory: ClimbCategory | null;
  mapPolyline: string;
}

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

  /** The keys among `sourceKeys` already loaded (ADR-039 §10: the import is idempotent on them). */
  async existingSourceKeys(sourceKeys: string[]): Promise<Set<string>> {
    if (sourceKeys.length === 0) {
      return new Set();
    }
    const rows = await this.db
      .select({ sourceKey: schema.segment.sourceKey })
      .from(schema.segment)
      .where(inArray(schema.segment.sourceKey, sourceKeys));
    return new Set(rows.map((row) => row.sourceKey!));
  }

  /**
   * A Segment created by Nervo (ADR-039 §5, §10): no creator, unverified, figures from the
   * generator. `false` when its source key is already there (a concurrent run).
   */
  async insertNervo(segment: NervoSegmentToInsert): Promise<boolean> {
    const [start, end] = [segment.path[0]!, segment.path.at(-1)!];
    const point = ([lon, lat]: readonly number[]) => `SRID=4326;POINT(${lon} ${lat})`;
    const rows = await this.db
      .insert(schema.segment)
      .values({
        name: segment.name,
        sportTypeCode: segment.sportTypeCode,
        origin: "nervo",
        createdBy: null,
        sourceKey: segment.sourceKey,
        path: `SRID=4326;LINESTRING Z(${segment.path.map((coordinate) => coordinate.join(" ")).join(",")})`,
        startPoint: point(start),
        endPoint: point(end),
        distanceM: segment.distanceM,
        avgGrade: segment.avgGrade,
        maxGrade: segment.maxGrade,
        elevationGainM: segment.elevationGainM,
        minAltitudeM: segment.minAltitudeM,
        maxAltitudeM: segment.maxAltitudeM,
        climbCategory: segment.climbCategory,
        mapPolyline: segment.mapPolyline,
      })
      .onConflictDoNothing({ target: schema.segment.sourceKey })
      .returning({ id: schema.segment.id });
    return rows.length > 0;
  }

  /** Deletes a Segment, cascading to its Efforts and stars; its provenance, if it existed. */
  async deleteReturningProvenance(
    id: string,
    tx: DbExecutor = this.db,
  ): Promise<{ origin: "athlete" | "nervo"; sourceKey: string | null } | undefined> {
    const [row] = await tx
      .delete(schema.segment)
      .where(eq(schema.segment.id, id))
      .returning({ origin: schema.segment.origin, sourceKey: schema.segment.sourceKey });
    return row;
  }

  /** ADR-039 §7: the last retro-matching page is done. */
  async markHistoryMatched(id: string): Promise<void> {
    await this.db
      .update(schema.segment)
      .set({ historyMatchedAt: sql`now()` })
      .where(eq(schema.segment.id, id));
  }
}
