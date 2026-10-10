import { Inject, Injectable } from "@nestjs/common";
import { and, asc, desc, eq, sql } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import type { ItineraryElevationSource } from "@repo/contracts";
import type { LonLat } from "@repo/geo";
import { DATABASE, type DbExecutor } from "../../infrastructure/index.js";
import type { ItineraryCursor } from "../domain/itinerary-cursor.js";
import { parseGeoJsonLineStringZ, toLineStringZEwkt } from "./geometry-format.js";

const t = schema.itinerary;

/** The columns a full save writes (create, and the full update of ADR-030 §6). */
export interface ItineraryValues {
  name: string;
  sportTypeCode: string;
  distanceM: number;
  elevationGainM: number;
  elevationSource: ItineraryElevationSource;
  /** Points every ~20 m with their altitude (`LineStringZ`). */
  track: (LonLat & { altitudeM: number })[];
  mapPolyline: string;
}

/** `updated_at` with PostgreSQL's microseconds, for the list cursor. */
const updatedAtMicros = sql<string>`to_char(${t.updatedAt} at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')`;

/** Reads and writes on `itineraries.itinerary` only (ADR-021 §6). */
@Injectable()
export class ItineraryRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  /** Owner of an id, whoever it is: tells a replay from an id conflict. */
  findOwnerId(id: string): Promise<string | undefined> {
    return this.db
      .select({ userId: t.userId })
      .from(t)
      .where(eq(t.id, id))
      .then((rows) => rows[0]?.userId);
  }

  /** Idempotent insert; `false` when the id already exists (a concurrent replay). */
  async insertIfAbsent(
    values: ItineraryValues & { id: string; userId: string },
    executor: DbExecutor = this.db,
  ): Promise<boolean> {
    const inserted = await executor
      .insert(t)
      .values({ ...values, track: toLineStringZEwkt(values.track) })
      .onConflictDoNothing({ target: t.id })
      .returning({ id: t.id });
    return inserted.length > 0;
  }

  /**
   * Full update of the athlete's Itinerary (ADR-030 §6), `updated_at`
   * included; `false` if unknown or someone else's.
   */
  async update(
    userId: string,
    id: string,
    values: ItineraryValues,
    executor: DbExecutor = this.db,
  ): Promise<boolean> {
    const updated = await executor
      .update(t)
      .set({ ...values, track: toLineStringZEwkt(values.track), updatedAt: sql`now()` })
      .where(and(eq(t.id, id), eq(t.userId, userId)))
      .returning({ id: t.id });
    return updated.length > 0;
  }

  /** Renames the athlete's Itinerary and moves `updated_at`; `false` if unknown or someone else's. */
  async rename(userId: string, id: string, name: string): Promise<boolean> {
    const renamed = await this.db
      .update(t)
      .set({ name, updatedAt: sql`now()` })
      .where(and(eq(t.id, id), eq(t.userId, userId)))
      .returning({ id: t.id });
    return renamed.length > 0;
  }

  /**
   * Hard delete of the athlete's Itinerary (ADR-017); its Waypoints and
   * Legs go in cascade. `false` if unknown or someone else's.
   */
  async delete(userId: string, id: string): Promise<boolean> {
    const deleted = await this.db
      .delete(t)
      .where(and(eq(t.id, id), eq(t.userId, userId)))
      .returning({ id: t.id });
    return deleted.length > 0;
  }

  /** The athlete's Itinerary with its track decoded; undefined if unknown or someone else's. */
  async findOwned(userId: string, id: string) {
    const [row] = await this.db
      .select({
        id: t.id,
        name: t.name,
        sportTypeCode: t.sportTypeCode,
        distanceM: t.distanceM,
        elevationGainM: t.elevationGainM,
        elevationSource: t.elevationSource,
        track: sql<string>`ST_AsGeoJSON(${t.track})`,
        createdAt: t.createdAt,
        updatedAt: t.updatedAt,
      })
      .from(t)
      .where(and(eq(t.id, id), eq(t.userId, userId)));
    return row ? { ...row, track: parseGeoJsonLineStringZ(row.track) } : undefined;
  }

  /**
   * One page of the athlete's list, keyset-paginated on `(updated_at desc,
   * id)` (`itinerary_user_updated_at_idx`). Returns up to `limit + 1` rows
   * so the caller knows whether a next page exists.
   */
  findPage(params: { userId: string; after?: ItineraryCursor; limit: number }) {
    const { userId, after, limit } = params;
    return this.db
      .select({
        id: t.id,
        name: t.name,
        sportTypeCode: t.sportTypeCode,
        distanceM: t.distanceM,
        elevationGainM: t.elevationGainM,
        mapPolyline: t.mapPolyline,
        updatedAt: t.updatedAt,
        cursorUpdatedAt: updatedAtMicros,
      })
      .from(t)
      .where(
        and(
          eq(t.userId, userId),
          after
            ? sql`(${t.updatedAt} < ${after.updatedAt}::timestamptz or (${t.updatedAt} = ${after.updatedAt}::timestamptz and ${t.id} > ${after.id}::uuid))`
            : undefined,
        ),
      )
      .orderBy(desc(t.updatedAt), asc(t.id))
      .limit(limit + 1);
  }
}
