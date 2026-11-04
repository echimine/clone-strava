import { Inject, Injectable } from "@nestjs/common";
import { and, count, desc, eq, gte, inArray, lt, sql, type SQL } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE, containsIgnoringAccents, offsetPage, parisDayRange } from "../../infrastructure/index.js";
import type { ActivityLabel, AdminActivityFilter, AdminActivityRow } from "../domain/admin-activity.js";

/**
 * The backoffice's reads and writes on `activities.activity` and `activity_track` (ADR-038 §11),
 * kept apart from the app's `ActivityRepository`.
 *
 * The list's search also reads the author's name and e-mail (`public.user`, `users.user_profile`)
 * in the same query, as the backoffice users list does: a read-only join for filtering, nothing
 * of the author leaves this repository.
 */
@Injectable()
export class AdminActivityRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  /** One page, newest created first, and the number of matching Activities. */
  async findPage(
    filter: AdminActivityFilter,
    page: { page: number; pageSize: number },
  ): Promise<{ rows: AdminActivityRow[]; total: number }> {
    const a = schema.activity;
    const where = and(...this.conditions(filter));
    const { limit, offset } = offsetPage(page);
    const base = this.db
      .select({
        id: a.id,
        userId: a.userId,
        title: a.title,
        sportTypeCode: a.sportTypeCode,
        processingStatus: a.processingStatus,
        source: a.source,
        visibility: a.visibility,
        startedAt: a.startedAt,
        createdAt: a.createdAt,
        distanceM: schema.activityStats.distanceM,
      })
      .from(a)
      .leftJoin(schema.activityStats, eq(schema.activityStats.activityId, a.id))
      .leftJoin(schema.user, eq(schema.user.id, a.userId))
      .leftJoin(schema.userProfile, eq(schema.userProfile.userId, a.userId))
      .where(where)
      .orderBy(desc(a.createdAt), desc(a.id))
      .limit(limit)
      .offset(offset);
    const counted = this.db
      .select({ total: count() })
      .from(a)
      .leftJoin(schema.user, eq(schema.user.id, a.userId))
      .leftJoin(schema.userProfile, eq(schema.userProfile.userId, a.userId))
      .where(where);
    const [rows, [total]] = await Promise.all([base, counted]);
    return { rows, total: total?.total ?? 0 };
  }

  /** The public trace as `[longitude, latitude]` pairs, and the start's place name. */
  async findPublicTrack(
    activityId: string,
  ): Promise<{ route: [number, number][] | null; locationName: string | null } | undefined> {
    const [row] = await this.db
      .select({
        route: sql<string | null>`ST_AsGeoJSON(${schema.activityTrack.route})`,
        locationName: schema.activityTrack.locationName,
      })
      .from(schema.activityTrack)
      .where(eq(schema.activityTrack.activityId, activityId));
    if (!row) {
      return undefined;
    }
    const geometry = row.route ? (JSON.parse(row.route) as { coordinates: number[][] }) : null;
    return {
      route: geometry ? geometry.coordinates.map(([lng, lat]) => [lng!, lat!] as [number, number]) : null,
      locationName: row.locationName,
    };
  }

  /** Number of an athlete's Activities and start of the latest (user sheet, ADR-038 §5). */
  async findSummary(userId: string): Promise<{ activityCount: number; lastActivityAt: Date | null }> {
    const [row] = await this.db
      .select({
        activityCount: sql<number>`count(*)::int`,
        lastActivityAt: sql<string | null>`max(${schema.activity.startedAt})`,
      })
      .from(schema.activity)
      .where(eq(schema.activity.userId, userId));
    return {
      activityCount: row?.activityCount ?? 0,
      lastActivityAt: row?.lastActivityAt ? new Date(row.lastActivityAt) : null,
    };
  }

  /** How e-mails and the backoffice name these Activities (ADR-038 §4). */
  findLabels(ids: string[]): Promise<ActivityLabel[]> {
    if (ids.length === 0) {
      return Promise.resolve([]);
    }
    const a = schema.activity;
    return this.db
      .select({ id: a.id, userId: a.userId, title: a.title, startedAt: a.startedAt })
      .from(a)
      .where(inArray(a.id, ids));
  }

  /**
   * « Retraiter » (ADR-019 §6, ADR-038 §11): `failed` -> `processing` with the error cleared, in
   * one statement; `false` unless the Activity was `failed`.
   */
  async resetFailedToProcessing(id: string): Promise<boolean> {
    const a = schema.activity;
    const updated = await this.db
      .update(a)
      .set({ processingStatus: "processing", processingError: null })
      .where(and(eq(a.id, id), eq(a.processingStatus, "failed")))
      .returning({ id: a.id });
    return updated.length > 0;
  }

  /** Replaces title and description whatever the processing state; `false` when it is gone. */
  async replaceText(id: string, text: { title: string; description: null }): Promise<boolean> {
    const a = schema.activity;
    const updated = await this.db
      .update(a)
      .set({ ...text, updatedAt: new Date() })
      .where(eq(a.id, id))
      .returning({ id: a.id });
    return updated.length > 0;
  }

  /** The ids among `ids` of Media that still exist (Journal links, ADR-038 §3). */
  async findExistingMediaIds(ids: string[]): Promise<Set<string>> {
    if (ids.length === 0) {
      return new Set();
    }
    const rows = await this.db
      .select({ id: schema.activityMedia.id })
      .from(schema.activityMedia)
      .where(inArray(schema.activityMedia.id, ids));
    return new Set(rows.map((row) => row.id));
  }

  private conditions(filter: AdminActivityFilter): SQL[] {
    const a = schema.activity;
    const { start, end } = parisDayRange(filter);
    return [
      filter.q
        ? containsIgnoringAccents(
            [a.title, schema.user.name, schema.user.email, schema.userProfile.firstName, schema.userProfile.lastName],
            filter.q,
          )
        : undefined,
      filter.status ? eq(a.processingStatus, filter.status) : undefined,
      filter.source ? eq(a.source, filter.source) : undefined,
      filter.sportTypeCode ? eq(a.sportTypeCode, filter.sportTypeCode) : undefined,
      filter.visibility ? eq(a.visibility, filter.visibility) : undefined,
      filter.userId ? eq(a.userId, filter.userId) : undefined,
      start ? gte(a.startedAt, start) : undefined,
      end ? lt(a.startedAt, end) : undefined,
    ].filter((condition): condition is SQL => condition !== undefined);
  }
}
