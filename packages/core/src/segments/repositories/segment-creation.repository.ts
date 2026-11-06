import { Inject, Injectable } from "@nestjs/common";
import { and, count, eq, gt, isNotNull, ne, notExists, sql } from "drizzle-orm";
import { alias } from "drizzle-orm/pg-core";
import { schema, type Database } from "@repo/db";
import type { LonLat } from "@repo/geo";
import { DATABASE, type DbExecutor } from "../../infrastructure/index.js";
import type { ClimbCategory } from "../domain/climb-category.js";
import type { SegmentFigures } from "../domain/segment-geometry.js";

const t = schema.segment;
const creation = schema.segmentCreation;
const effort = alias(schema.segmentEffort, "other_effort");

/** A new Segment drawn by an athlete, everything computed (ADR-039 §5). */
export interface NewAthleteSegment {
  name: string;
  sportTypeCode: string;
  createdBy: string;
  figures: SegmentFigures;
  track: Array<LonLat & { altitudeM: number }>;
  mapPolyline: string;
}

/** A stored Segment as its creation answers it. */
export interface StoredSegment {
  id: string;
  name: string;
  sportTypeCode: string;
  verifiedAt: Date | null;
  distanceM: number;
  elevationGainM: number;
  avgGrade: number;
  maxGrade: number;
  minAltitudeM: number;
  maxAltitudeM: number;
  climbCategory: ClimbCategory | null;
  createdAt: Date;
}

const pointEwkt = (point: LonLat) => `SRID=4326;POINT(${point.lon} ${point.lat})`;
const lineStringZEwkt = (points: Array<LonLat & { altitudeM: number }>) =>
  `SRID=4326;LINESTRING Z(${points.map((p) => `${p.lon} ${p.lat} ${p.altitudeM}`).join(",")})`;

/** Creation, rename and deletion of `segments.segment` (ADR-021 §6, ADR-039 §5, §11). */
@Injectable()
export class SegmentCreationRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  /** Serializes one athlete's creations, so the quota is counted once per creation. */
  async lockCreator(userId: string, tx: DbExecutor): Promise<void> {
    await tx.execute(sql`select pg_advisory_xact_lock(hashtextextended(${`segments.create:${userId}`}, 0))`);
  }

  /**
   * The athlete's creations of the last `hours`, deleted Segments included (ADR-039 §5), and the
   * seconds until the oldest leaves that window.
   */
  async countRecent(
    userId: string,
    hours: number,
    executor: DbExecutor = this.db,
  ): Promise<{ total: number; secondsUntilOldestExpires: number | null }> {
    const since = sql`now() - make_interval(hours => ${hours})`;
    const [row] = await executor
      .select({
        total: count(),
        secondsUntilOldestExpires: sql<
          string | null
        >`ceil(extract(epoch from (min(${creation.createdAt}) + make_interval(hours => ${hours}) - now())))`,
      })
      .from(creation)
      .where(and(eq(creation.userId, userId), gt(creation.createdAt, since)));
    const seconds = row?.secondsUntilOldestExpires;
    return { total: row?.total ?? 0, secondsUntilOldestExpires: seconds === null || seconds === undefined ? null : Number(seconds) };
  }

  /**
   * Segments of the sport whose start and end lie within `marginDeg` of the new path's: the only
   * candidates to a both-ways duplicate (ADR-039 §5), through the GiST indexes.
   */
  async findDuplicateCandidates(
    sportTypeCode: string,
    ends: { start: LonLat; end: LonLat },
    marginDeg: number,
    executor: DbExecutor = this.db,
  ): Promise<Array<{ id: string; name: string; path: LonLat[] }>> {
    const rows = await executor
      .select({ id: t.id, name: t.name, path: sql<string>`ST_AsGeoJSON(${t.path})` })
      .from(t)
      .where(
        and(
          eq(t.sportTypeCode, sportTypeCode),
          isNotNull(t.path),
          sql`ST_DWithin(${t.startPoint}, ST_GeomFromEWKT(${pointEwkt(ends.start)}), ${marginDeg})`,
          sql`ST_DWithin(${t.endPoint}, ST_GeomFromEWKT(${pointEwkt(ends.end)}), ${marginDeg})`,
        ),
      )
      .orderBy(t.createdAt);
    return rows.map((row) => ({
      id: row.id,
      name: row.name,
      path: (JSON.parse(row.path) as { coordinates: number[][] }).coordinates.map(([lon, lat]) => ({ lat: lat!, lon: lon! })),
    }));
  }

  /** Inserts the Segment (`origin = athlete`), journals the creation and stars it for its creator. */
  async insert(segment: NewAthleteSegment, tx: DbExecutor): Promise<StoredSegment> {
    const { figures, track } = segment;
    const [row] = await tx
      .insert(t)
      .values({
        name: segment.name,
        sportTypeCode: segment.sportTypeCode,
        createdBy: segment.createdBy,
        origin: "athlete",
        path: sql`ST_GeomFromEWKT(${lineStringZEwkt(track)})`,
        startPoint: sql`ST_GeomFromEWKT(${pointEwkt(track[0]!)})`,
        endPoint: sql`ST_GeomFromEWKT(${pointEwkt(track.at(-1)!)})`,
        distanceM: figures.distanceM,
        avgGrade: figures.avgGradePct,
        maxGrade: figures.maxGradePct,
        elevationGainM: figures.elevationGainM,
        minAltitudeM: figures.minAltitudeM,
        maxAltitudeM: figures.maxAltitudeM,
        climbCategory: figures.climbCategory,
        mapPolyline: segment.mapPolyline,
      })
      .returning({
        id: t.id,
        name: t.name,
        sportTypeCode: t.sportTypeCode,
        verifiedAt: t.verifiedAt,
        distanceM: t.distanceM,
        elevationGainM: t.elevationGainM,
        avgGrade: t.avgGrade,
        maxGrade: t.maxGrade,
        minAltitudeM: t.minAltitudeM,
        maxAltitudeM: t.maxAltitudeM,
        climbCategory: t.climbCategory,
        createdAt: t.createdAt,
      });
    await tx.insert(creation).values({ userId: segment.createdBy });
    await tx.insert(schema.segmentFavorite).values({ userId: segment.createdBy, segmentId: row!.id });
    return row as StoredSegment;
  }

  /** Who created the Segment; `undefined` when unknown. */
  async findCreator(id: string): Promise<{ createdBy: string | null } | undefined> {
    const [row] = await this.db.select({ createdBy: t.createdBy }).from(t).where(eq(t.id, id));
    return row;
  }

  async rename(id: string, name: string): Promise<void> {
    await this.db.update(t).set({ name, updatedAt: sql`now()` }).where(eq(t.id, id));
  }

  /**
   * Deletes the Segment unless an athlete other than its creator has an Effort on it, in one
   * statement so a concurrent retro-matching cannot slip in between (ADR-039 §5, §11). The
   * cascade takes its Efforts (and their verdicts) and favourites. `false` when kept.
   */
  async deleteUnlessOthersHaveEfforts(id: string, creatorId: string): Promise<boolean> {
    const deleted = await this.db
      .delete(t)
      .where(and(eq(t.id, id), eq(t.createdBy, creatorId), notExists(this.othersEfforts(creatorId))))
      .returning({ id: t.id });
    return deleted.length === 1;
  }

  /**
   * ADR-039 §11: before an account is deleted, its Segments nobody else has an Effort on; the
   * others keep going with `created_by = null`. Returns how many were deleted.
   */
  async deleteOnlyTheirs(userId: string): Promise<number> {
    const deleted = await this.db
      .delete(t)
      .where(and(eq(t.createdBy, userId), notExists(this.othersEfforts(userId))))
      .returning({ id: t.id });
    return deleted.length;
  }

  /** An Effort on the outer Segment by anyone but `userId`, whatever its verdict. */
  private othersEfforts(userId: string) {
    return this.db
      .select({ one: sql`1` })
      .from(effort)
      .where(and(eq(effort.segmentId, t.id), ne(effort.userId, userId)));
  }
}
