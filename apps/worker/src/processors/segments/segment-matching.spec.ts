import { randomUUID } from "node:crypto";
import { gzipSync } from "node:zlib";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { getQueueToken } from "@nestjs/bullmq";
import type { Queue } from "bullmq";
import {
  MATCH_SEGMENT_HISTORY_JOB_NAME,
  SEGMENTS_QUEUE_NAME,
  TRACE_SCHEMA_VERSION,
  activityTraceKey,
  matchSegmentHistoryJobId,
  matchSegmentsVersionJobId,
} from "@repo/contracts";
import { ActivitiesService } from "@repo/core/activities";
import { NO_EXCLUSIONS } from "@repo/core/infrastructure";
import { SEGMENT_MATCHING_VERSION, SegmentsService } from "@repo/core/segments";
import { bootstrapTestWorkerApp, waitFor, type TestWorkerApp } from "../../testing/test-worker-app.js";

const M_PER_DEG_LAT = (6_371_000 * Math.PI) / 180;
const DAY_MS = 86_400_000;

/** A place of its own for each test, so Segments of other tests are never candidates. */
function newPlace() {
  const lat = 44 + Math.random() * 4;
  const lon = 1 + Math.random() * 5;
  const mPerDegLon = M_PER_DEG_LAT * Math.cos((lat * Math.PI) / 180);
  return {
    /** A point `x` meters east, `y` meters north of the place. */
    at: (x: number, y = 0) => ({ lat: lat + y / M_PER_DEG_LAT, lon: lon + x / mPerDegLon }),
  };
}
type Place = ReturnType<typeof newPlace>;

/**
 * Gzipped trace straight east from `fromM` to `toM` at `speedMs`, one point per second: the
 * 1 km Segment from 0 to 1,000 m takes 1,000 / `speedMs` seconds.
 */
function eastTrace(place: Place, start: Date, speedMs: number, fromM = -200, toM = 1200): Uint8Array {
  const count = Math.floor((toM - fromM) / speedMs);
  return gzipSync(
    JSON.stringify({
      schemaVersion: TRACE_SCHEMA_VERSION,
      points: Array.from({ length: count + 1 }, (_, i) => ({
        timestampMs: start.getTime() + i * 1000,
        ...place.at(fromM + i * speedMs),
        elevationM: 100,
        horizontalAccuracyM: 5,
      })),
      pauses: [],
    }),
  );
}

/**
 * Segment matching (ADR-039 §6-§8, §13) on real Postgres and Redis: `match-segments` after
 * `process-activity` and after a sport change, the retro-matching of a new Segment, the Medal
 * replays and the reconciliation sweep.
 */
describe("Segment matching (integration)", () => {
  let ctx: TestWorkerApp;
  let activities: ActivitiesService;
  const users: string[] = [];
  const segments: string[] = [];

  beforeAll(async () => {
    ctx = await bootstrapTestWorkerApp();
    activities = ctx.app.get(ActivitiesService);
  }, 30_000);

  afterAll(async () => {
    if (segments.length > 0) {
      await ctx.db.$client.query("delete from segments.segment where id = any($1::uuid[])", [segments]);
    }
    for (const userId of users) {
      await ctx.db.$client.query('delete from "user" where id = $1', [userId]);
    }
    await ctx?.close();
  });

  async function sql<T = Record<string, unknown>>(text: string, values: unknown[] = []): Promise<T[]> {
    return (await ctx.db.$client.query(text, values)).rows as T[];
  }

  async function newAthlete(): Promise<string> {
    const userId = randomUUID();
    users.push(userId);
    await sql('insert into "user" (id, name, email) values ($1, $2, $3)', [userId, "Segments test", `${userId}@test.local`]);
    return userId;
  }

  /** A 1 km Segment heading east from the place. */
  async function newSegment(place: Place, sportTypeCode = "run", createdBy: string | null = null): Promise<string> {
    const id = randomUUID();
    segments.push(id);
    const start = place.at(0);
    const end = place.at(1000);
    await sql(
      `insert into segments.segment (id, name, sport_type_code, created_by, path, start_point, end_point, distance_m)
       values ($1, 'Ligne droite', $2, $3,
         ST_GeomFromEWKT($4), ST_SetSRID(ST_MakePoint($5, $6), 4326), ST_SetSRID(ST_MakePoint($7, $8), 4326), 1000)`,
      [
        id,
        sportTypeCode,
        createdBy,
        `SRID=4326;LINESTRING Z(${start.lon} ${start.lat} 100,${end.lon} ${end.lat} 110)`,
        start.lon,
        start.lat,
        end.lon,
        end.lat,
      ],
    );
    return id;
  }

  /** Records and processes an Activity east across the place; returns its id. */
  async function processedActivity(
    userId: string,
    place: Place,
    {
      daysAgo = 1,
      speedMs = 5,
      sportTypeCode = "run",
      visibility = "public",
    }: { daysAgo?: number; speedMs?: number; sportTypeCode?: string; visibility?: "public" | "followers" | "private" } = {},
  ): Promise<string> {
    const id = randomUUID();
    const start = new Date(Date.now() - daysAgo * DAY_MS);
    await activities.create(userId, {
      id,
      sportTypeCode,
      title: "Sortie",
      startedAt: start.toISOString(),
      endedAt: new Date(start.getTime() + (1400 / speedMs) * 1000).toISOString(),
      visibility,
      isManual: false,
    });
    ctx.storage.objects.set(activityTraceKey(userId, id), eastTrace(place, start, speedMs));
    await activities.complete(userId, id);
    await waitFor(async () => {
      const detail = await activities.getDetail(userId, id, NO_EXCLUSIONS);
      return detail.processingStatus === "processed" ? true : undefined;
    });
    return id;
  }

  /** The Activity's matching version once `match-segments` has run. */
  function matched(activityId: string): Promise<number> {
    return waitFor(async () => {
      const [row] = await sql<{ version: number }>(
        "select version from segments.activity_matching where activity_id = $1",
        [activityId],
      );
      return row?.version;
    });
  }

  async function matchedNow(activityId: string): Promise<boolean> {
    const rows = await sql("select 1 from segments.activity_matching where activity_id = $1 and version = $2", [
      activityId,
      SEGMENT_MATCHING_VERSION,
    ]);
    return rows.length === 1;
  }

  function efforts(activityId: string) {
    return sql<{
      id: string;
      segment_id: string;
      elapsed_time_s: number;
      status: string;
      medal: string | null;
      start_index: number;
    }>(
      `select id, segment_id, elapsed_time_s, status, medal, start_index
         from segments.segment_effort where activity_id = $1 order by started_at`,
      [activityId],
    );
  }

  it("matches a new Activity after its processing: one Effort, gold, then the realtime event", async () => {
    const place = newPlace();
    const userId = await newAthlete();
    const segmentId = await newSegment(place);

    const activityId = await processedActivity(userId, place, { speedMs: 5 });

    expect(await matched(activityId)).toBe(1);
    expect(await efforts(activityId)).toEqual([
      expect.objectContaining({ segment_id: segmentId, elapsed_time_s: 200, status: "valid", medal: "gold" }),
    ]);
    await waitFor(async () =>
      ctx.realtimeMessages.some(
        (message) =>
          message.envelope.t === "activity.segments_matched" && message.envelope.data.activityId === activityId,
      )
        ? true
        : undefined,
    );
  }, 30_000);

  it("replays idempotently: keeps the Effort, drops the gone ones, passes a verdict on", async () => {
    const place = newPlace();
    const userId = await newAthlete();
    const segmentId = await newSegment(place);
    const activityId = await processedActivity(userId, place);
    await matched(activityId);
    const [effort] = await efforts(activityId);
    const service = ctx.app.get(SegmentsService);

    await service.matchSegments({ activityId, userId });
    expect((await efforts(activityId)).map((row) => row.id)).toEqual([effort!.id]);

    // As if an older algorithm had found it from another point, and rejected it; plus an Effort
    // on a Segment the trace no longer matches.
    await sql("update segments.segment_effort set start_index = start_index + 3, status = 'rejected' where id = $1", [
      effort!.id,
    ]);
    const otherSegment = await newSegment(newPlace());
    await sql(
      `insert into segments.segment_effort (activity_id, segment_id, user_id, elapsed_time_s, started_at, start_index,
         end_index, min_distance_to_activity_start_m, min_distance_to_activity_end_m)
       values ($1, $2, $3, 100, now(), 0, 100, 0, 0)`,
      [activityId, otherSegment, userId],
    );

    await service.matchSegments({ activityId, userId });

    const after = await efforts(activityId);
    expect(after).toEqual([
      expect.objectContaining({ segment_id: segmentId, start_index: effort!.start_index, status: "rejected", medal: null }),
    ]);
    expect(after[0]!.id).not.toBe(effort!.id);
  }, 30_000);

  it("replays the athlete's Medals in date order, and again once an Activity is deleted", async () => {
    const place = newPlace();
    const userId = await newAthlete();
    await newSegment(place);
    const slow = await processedActivity(userId, place, { daysAgo: 5, speedMs: 4 });
    const fast = await processedActivity(userId, place, { daysAgo: 3, speedMs: 5, visibility: "private" });
    await Promise.all([matched(slow), matched(fast)]);
    // Imported afterwards, between the two in time, as fast as the second.
    const middle = await processedActivity(userId, place, { daysAgo: 4, speedMs: 5 });
    await matched(middle);

    const medalOf = async (activityId: string) => (await efforts(activityId))[0]!.medal;
    expect([await medalOf(slow), await medalOf(middle), await medalOf(fast)]).toEqual(["gold", "gold", "silver"]);

    await activities.delete(userId, middle);

    await waitFor(async () => ((await medalOf(fast)) === "gold" ? true : undefined));
    expect(await medalOf(slow)).toBe("gold");
  }, 60_000);

  it("marks a too fast Effort suspicious, except on a private Activity", async () => {
    const place = newPlace();
    const userId = await newAthlete();
    await newSegment(place);
    // 8 m/s is 28.8 km/h: plausible for the cleanup (12 m/s), above 25 km/h on a Segment.
    const open = await processedActivity(userId, place, { speedMs: 8, daysAgo: 2 });
    const hidden = await processedActivity(userId, place, { speedMs: 8, daysAgo: 1, visibility: "private" });
    await Promise.all([matched(open), matched(hidden)]);

    expect((await efforts(open))[0]).toMatchObject({ status: "suspicious", medal: "gold" });
    expect((await efforts(hidden))[0]).toMatchObject({ status: "valid", medal: "silver" });
  }, 60_000);

  it("writes the matching version of a sport without Segments, with no Effort", async () => {
    const place = newPlace();
    const userId = await newAthlete();
    await newSegment(place, "run");
    const swim = await processedActivity(userId, place, { sportTypeCode: "swim", speedMs: 2 });

    expect(await matched(swim)).toBe(1);
    expect(await efforts(swim)).toEqual([]);
  }, 30_000);

  it("writes the matching version of a sport without Segments during the sweep, without a job", async () => {
    const place = newPlace();
    const userId = await newAthlete();
    const swim = await processedActivity(userId, place, { sportTypeCode: "swim", speedMs: 2 });
    await matched(swim);
    // Processed before the matching existed: no row, and no job of today's version left.
    await sql("delete from segments.activity_matching where activity_id = $1", [swim]);
    const queue = ctx.app.get<Queue>(getQueueToken(SEGMENTS_QUEUE_NAME));
    await (await queue.getJob(matchSegmentsVersionJobId(swim, SEGMENT_MATCHING_VERSION)))?.remove();

    await waitFor(async () => {
      if (await matchedNow(swim)) {
        return true;
      }
      await queue.add("reconcile-segment-matching", {});
      await new Promise((resolve) => setTimeout(resolve, 400));
      return undefined;
    }, 30_000);

    expect(await queue.getJob(matchSegmentsVersionJobId(swim, SEGMENT_MATCHING_VERSION))).toBeUndefined();
  }, 60_000);

  it("matches again at the end of reprocess-activity when the sport changed", async () => {
    const place = newPlace();
    const userId = await newAthlete();
    const runSegment = await newSegment(place, "run");
    const rideSegment = await newSegment(place, "ride");
    const activityId = await processedActivity(userId, place);
    await matched(activityId);
    expect((await efforts(activityId)).map((row) => row.segment_id)).toEqual([runSegment]);

    await activities.update(userId, activityId, { sportTypeCode: "ride" });

    const after = await waitFor(async () => {
      const rows = await efforts(activityId);
      return rows[0]?.segment_id === rideSegment ? rows : undefined;
    });
    expect(after).toEqual([expect.objectContaining({ segment_id: rideSegment, medal: "gold" })]);
  }, 60_000);

  it("retro-matches a new Segment on every visibility, the creator's Activities first, then marks it done", async () => {
    const place = newPlace();
    const creator = await newAthlete();
    const other = await newAthlete();
    const mine = await processedActivity(creator, place, { daysAgo: 3 });
    const theirs = await processedActivity(other, place, { daysAgo: 2, visibility: "private" });
    const ride = await processedActivity(other, place, { daysAgo: 1, sportTypeCode: "ride" });
    await Promise.all([matched(mine), matched(theirs), matched(ride)]);
    // Drawn afterwards: only the retro-matching finds the past Efforts.
    const segmentId = await newSegment(place, "run", creator);

    const queue = ctx.app.get<Queue>(getQueueToken(SEGMENTS_QUEUE_NAME));
    await queue.add(
      MATCH_SEGMENT_HISTORY_JOB_NAME,
      { segmentId, cursor: null },
      { jobId: matchSegmentHistoryJobId(segmentId, null) },
    );

    await waitFor(async () => {
      const [row] = await sql<{ history_matched_at: Date | null }>(
        "select history_matched_at from segments.segment where id = $1",
        [segmentId],
      );
      return row?.history_matched_at ?? undefined;
    });
    expect(await efforts(mine)).toEqual([expect.objectContaining({ segment_id: segmentId, medal: "gold" })]);
    expect(await efforts(theirs)).toEqual([expect.objectContaining({ segment_id: segmentId, medal: "gold" })]);
    expect(await efforts(ride)).toEqual([]);
  }, 60_000);

  it("stops the retro-matching of a deleted Segment", async () => {
    const place = newPlace();
    const segmentId = await newSegment(place);
    await sql("delete from segments.segment where id = $1", [segmentId]);

    expect(await ctx.app.get(SegmentsService).matchSegmentHistory({ segmentId, cursor: null })).toBeNull();
  });

  it("enqueues the processed Activities never matched or matched with an older version", async () => {
    const place = newPlace();
    const userId = await newAthlete();
    const segmentId = await newSegment(place);
    const lost = await processedActivity(userId, place, { daysAgo: 2 });
    const outdated = await processedActivity(userId, place, { daysAgo: 1 });
    await Promise.all([matched(lost), matched(outdated)]);
    // A lost job, and a version older than today's.
    await sql("delete from segments.segment_effort where activity_id = any($1::uuid[])", [[lost, outdated]]);
    await sql("delete from segments.activity_matching where activity_id = $1", [lost]);
    await sql("update segments.activity_matching set version = 0 where activity_id = $1", [outdated]);

    // The sweep takes 100 at a time, oldest id first: run it until both are matched again.
    const queue = ctx.app.get<Queue>(getQueueToken(SEGMENTS_QUEUE_NAME));
    await waitFor(async () => {
      const rows = await sql<{ version: number }>(
        "select version from segments.activity_matching where activity_id = any($1::uuid[]) and version = 1",
        [[lost, outdated]],
      );
      if (rows.length === 2) {
        return true;
      }
      await queue.add("reconcile-segment-matching", {});
      await new Promise((resolve) => setTimeout(resolve, 400));
      return undefined;
    }, 30_000);
    expect((await efforts(lost)).map((row) => row.segment_id)).toEqual([segmentId]);
    expect((await efforts(outdated)).map((row) => row.segment_id)).toEqual([segmentId]);
  }, 60_000);
});
