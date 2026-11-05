import { randomUUID } from "node:crypto";
import { BullModule, getQueueToken } from "@nestjs/bullmq";
import { APP_FILTER, APP_INTERCEPTOR, APP_PIPE } from "@nestjs/core";
import { EventEmitterModule } from "@nestjs/event-emitter";
import type { NestExpressApplication } from "@nestjs/platform-express";
import { Test } from "@nestjs/testing";
import type { Queue } from "bullmq";
import { ZodSerializerInterceptor, ZodValidationPipe } from "nestjs-zod";
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi, type MockInstance } from "vitest";
import {
  ANALYTICS_EVENTS,
  MATCH_SEGMENT_HISTORY_JOB_NAME,
  SEGMENT_JOB_PRIORITY,
  SEGMENTS_QUEUE_NAME,
  matchSegmentHistoryJobId,
  type CreatedSegment,
  type ListSegmentFavoritesResponse,
  type SegmentPreview,
} from "@repo/contracts";
import { AnalyticsModule, AnalyticsService } from "@repo/core/analytics";
import { AuthService } from "@repo/core/auth";
import { ElevationModule } from "@repo/core/elevation";
import { GeocodingModule } from "@repo/core/geocoding";
import { StorageModule } from "@repo/core/storage";
import { CoreInfrastructureModule, DATABASE, type Database } from "@repo/core/infrastructure";
import { SegmentCreationModule, SegmentsModule } from "@repo/core/segments";
import { decodePolyline, type LonLat } from "@repo/geo";
import { ensureTestDatabaseMigrated, TEST_DATABASE_URL, TEST_REDIS_URL } from "../auth/test-auth-app.js";
import { SessionGuard } from "../auth/session.guard.js";
import { GlobalExceptionFilter } from "../common/global-exception.filter.js";
import { jsonBodyParser } from "../common/json-body.js";
import { listenOnLoopback } from "../testing/listen-on-loopback.js";
import { SegmentCreationController } from "./segment-creation.controller.js";

/** Meters per degree of latitude on the haversine sphere (R = 6,371,000 m). */
const M_PER_DEG_LAT = (6_371_000 * Math.PI) / 180;
const BASE_LAT = 45.9;

/** IGN's terrain: climbs 8 m every 100 m north of 45.9° N. */
const terrain = ({ lat }: LonLat) => 500 + (lat - BASE_LAT) * M_PER_DEG_LAT * 0.08;

/** Each test draws on its own meridian, 780 m apart, so that no Segment duplicates another's. */
let nextLane = 0;
function lane(): number {
  nextLane += 1;
  return 6.12 + nextLane * 0.01;
}

/** A point `northM` meters north of 45.9° N and `eastM` meters east of `lon`. */
function at(lon: number, northM: number, eastM = 0): LonLat {
  return {
    lat: BASE_LAT + northM / M_PER_DEG_LAT,
    lon: lon + eastM / (M_PER_DEG_LAT * Math.cos((BASE_LAT * Math.PI) / 180)),
  };
}

/** A straight path north along `lon`, from `fromM` to `toM`, drawn with a point every 100 m. */
function northPath(lon: number, toM: number, fromM = 0): LonLat[] {
  const points: LonLat[] = [];
  for (let m = fromM; m < toM; m += 100) points.push(at(lon, m));
  points.push(at(lon, toM));
  return points;
}

/**
 * Creating a Segment in the app over real HTTP (spec #249, ADR-039 §5, §11, §12): real Nest,
 * Postgres and Redis, sessions from `x-test-user`. Only the `elevation` module's `fetch` is
 * faked: IGN answers `terrain`.
 */
describe("Segment creation (integration)", () => {
  let app: NestExpressApplication;
  let baseUrl: string;
  let queue: Queue;
  let capture: MockInstance<AnalyticsService["capture"]>;
  let elevationDown = false;
  const users: string[] = [];

  const fakeFetch = async (input: string | URL | Request, init?: RequestInit): Promise<Response> => {
    const url = new URL(input instanceof Request ? input.url : String(input));
    if (elevationDown) return new Response("Bad gateway", { status: 502 });
    if (url.hostname !== "data.geopf.fr") throw new Error(`Unexpected request to ${url}`);
    const body = JSON.parse(String(init?.body)) as Record<string, string>;
    const lons = body.lon!.split("|").map(Number);
    const points = body.lat!.split("|").map((lat, i) => ({ lat: Number(lat), lon: lons[i]! }));
    return Response.json({ elevations: points.map(terrain) });
  };

  async function sql<Row = Record<string, unknown>>(text: string, params: unknown[] = []): Promise<Row[]> {
    return (await app.get<Database>(DATABASE).$client.query(text, params)).rows as Row[];
  }

  async function newAthlete(): Promise<string> {
    const id = randomUUID();
    await sql('insert into "user" (id, name, email) values ($1, $2, $3)', [id, "Athlète", `${id}@test.local`]);
    users.push(id);
    return id;
  }

  function call(path: string, user: string | null, init: { method?: string; body?: unknown } = {}) {
    return fetch(`${baseUrl}/v1${path}`, {
      method: init.method ?? "GET",
      headers: { "content-type": "application/json", ...(user ? { "x-test-user": user } : {}) },
      body: init.body === undefined ? undefined : JSON.stringify(init.body),
    });
  }

  const preview = (user: string, body: unknown) => call("/segments/preview", user, { method: "POST", body });
  const create = (user: string, body: unknown) => call("/segments", user, { method: "POST", body });
  const errorOf = async (response: Response) =>
    ((await response.json()) as { error: { code: string; existing?: { id: string; name: string } } }).error;

  async function createOne(user: string, body: Record<string, unknown>): Promise<CreatedSegment> {
    const response = await create(user, { sport: "run", name: "Montée du Semnoz", ...body });
    expect(response.status, await response.clone().text()).toBe(201);
    return (await response.json()) as CreatedSegment;
  }

  /** An Activity of `user` with one Effort on `segmentId`. */
  async function seedEffort(user: string, segmentId: string, elapsedTimeS: number, status = "valid") {
    const activityId = randomUUID();
    await sql(
      `insert into activities.activity (id, user_id, sport_type_code, title, started_at, ended_at, visibility, processing_status)
       values ($1, $2, 'run', 'Sortie', now(), now() + interval '1 hour', 'public', 'processed')`,
      [activityId, user],
    );
    await sql(
      `insert into segments.segment_effort (activity_id, segment_id, user_id, elapsed_time_s, started_at, start_index,
         end_index, min_distance_to_activity_start_m, min_distance_to_activity_end_m, status)
       values ($1, $2, $3, $4, now(), 0, 10, 1000, 1000, $5)`,
      [activityId, segmentId, user, elapsedTimeS, status],
    );
  }

  beforeAll(async () => {
    await ensureTestDatabaseMigrated();
    const moduleRef = await Test.createTestingModule({
      imports: [
        CoreInfrastructureModule.forRoot({ databaseUrl: TEST_DATABASE_URL, redisUrl: TEST_REDIS_URL }),
        BullModule.forRoot({ connection: { host: "127.0.0.1", port: 6379 }, prefix: `test-${randomUUID()}` }),
        AnalyticsModule.forRoot({}),
        EventEmitterModule.forRoot({ wildcard: true, delimiter: "." }),
        ElevationModule.forRoot({ fetch: fakeFetch as typeof fetch }),
        // `segments` reads `activities`, which needs them; never called here.
        StorageModule.forRoot({
          endpoint: "https://bucket.test",
          region: "test",
          bucket: "test",
          accessKeyId: "test",
          secretAccessKey: "test",
        }),
        GeocodingModule.forRoot({}),
        SegmentsModule,
        SegmentCreationModule,
      ],
      controllers: [SegmentCreationController],
      providers: [
        SessionGuard,
        {
          provide: AuthService,
          useValue: {
            getSession: async (headers: Headers) => {
              const userId = headers.get("x-test-user");
              return userId
                ? { userId, email: `${userId}@test.local`, name: "Test", role: "user", twoFactorEnabled: false }
                : null;
            },
          },
        },
        { provide: APP_PIPE, useClass: ZodValidationPipe },
        { provide: APP_INTERCEPTOR, useClass: ZodSerializerInterceptor },
        { provide: APP_FILTER, useClass: GlobalExceptionFilter },
      ],
    }).compile();

    app = moduleRef.createNestApplication<NestExpressApplication>({ bodyParser: false });
    app.use(jsonBodyParser());
    app.setGlobalPrefix("v1");
    baseUrl = await listenOnLoopback(app);
    queue = app.get<Queue>(getQueueToken(SEGMENTS_QUEUE_NAME));
    capture = vi.spyOn(app.get(AnalyticsService), "capture");
  }, 30_000);

  afterAll(async () => {
    await sql("delete from segments.segment where created_by = any($1)", [users]);
    await sql('delete from "user" where id = any($1)', [users]);
    await app?.close();
  });

  beforeEach(() => {
    elevationDown = false;
    capture.mockClear();
  });

  describe("POST /v1/segments/preview", () => {
    it("computes the figures of the drawn path with the ElevationService, writing nothing", async () => {
      const athlete = await newAthlete();
      const lon = lane();
      const response = await preview(athlete, { sport: "run", points: northPath(lon, 1_000) });
      expect(response.status, await response.clone().text()).toBe(200);
      const body = (await response.json()) as SegmentPreview;
      expect(body).toMatchObject({
        distanceM: 1_000,
        elevationGainM: 80,
        avgGradePct: 8,
        maxGradePct: 8,
        minAltitudeM: 500,
        maxAltitudeM: 580,
        climbCategory: "4",
        violations: [],
        duplicate: null,
        quotaLeft: 10,
      });
      // One point every 20 m, ends kept, each with its altitude.
      const track = decodePolyline(body.track.polyline6, 6);
      expect(track).toHaveLength(51);
      expect(body.track.altitudesM).toHaveLength(51);
      expect(body.track.altitudesM[0]).toBe(500);
      expect(body.track.altitudesM.at(-1)).toBe(580);
      expect(await sql("select 1 from segments.segment where created_by = $1", [athlete])).toEqual([]);
    });

    it("lists the broken rules instead of refusing: too short, and a loop", async () => {
      const athlete = await newAthlete();
      const lon = lane();
      const tooShort = await preview(athlete, { sport: "ride", points: northPath(lon, 400) });
      expect(((await tooShort.json()) as SegmentPreview).violations).toEqual(["too_short"]);
      const loop = await preview(athlete, {
        sport: "run",
        points: [at(lon, 0), at(lon, 400), at(lon, 400, 300), at(lon, 0, 50)],
      });
      expect(((await loop.json()) as SegmentPreview).violations).toEqual(["loop"]);
    });

    it("answers a retryable 503 when the ElevationService fails", async () => {
      const athlete = await newAthlete();
      elevationDown = true;
      const response = await preview(athlete, { sport: "run", points: northPath(lane(), 1_000) });
      expect(response.status).toBe(503);
      expect((await errorOf(response)).code).toBe("elevation_unavailable");
    });

    it("refuses a sport without a map (422)", async () => {
      const athlete = await newAthlete();
      const response = await preview(athlete, { sport: "swim", points: northPath(lane(), 1_000) });
      expect(response.status).toBe(422);
    });

    it("answers 401 without a session", async () => {
      expect((await call("/segments/preview", null, { method: "POST", body: {} })).status).toBe(401);
    });
  });

  describe("POST /v1/segments", () => {
    it("creates the Segment (201), stars it for its creator and starts the retro-matching", async () => {
      const athlete = await newAthlete();
      const lon = lane();
      const created = await createOne(athlete, { sport: "ride", name: "  Col du Semnoz  ", points: northPath(lon, 1_000) });
      expect(created).toMatchObject({
        name: "Col du Semnoz",
        sport: "ride",
        verified: false,
        distanceM: 1_000,
        elevationGainM: 80,
        avgGradePct: 8,
        climbCategory: "4",
      });

      const [row] = await sql<Record<string, unknown>>(
        `select origin, created_by, sport_type_code, distance_m, max_grade, min_altitude_m, max_altitude_m,
           climb_category, map_polyline is not null as has_polyline, ST_NPoints(path) as points, ST_Z(ST_EndPoint(path)) as end_z,
           ST_Distance(start_point::geography, ST_SetSRID(ST_MakePoint($2, $3), 4326)::geography) < 0.01 as start_ok
         from segments.segment where id = $1`,
        [created.id, lon, BASE_LAT],
      );
      expect(row).toEqual({
        origin: "athlete",
        created_by: athlete,
        sport_type_code: "ride",
        distance_m: 1_000,
        max_grade: 8,
        min_altitude_m: 500,
        max_altitude_m: 580,
        climb_category: "4",
        has_polyline: true,
        points: 51,
        end_z: 580,
        start_ok: true,
      });
      expect(await sql("select user_id from segments.segment_favorite where segment_id = $1", [created.id])).toEqual([
        { user_id: athlete },
      ]);

      const job = await queue.getJob(matchSegmentHistoryJobId(created.id, null));
      expect(job?.name).toBe(MATCH_SEGMENT_HISTORY_JOB_NAME);
      expect(job?.data).toEqual({ segmentId: created.id, cursor: null });
      expect(job?.opts.priority).toBe(SEGMENT_JOB_PRIORITY.history);
      expect(capture.mock.calls).toEqual([[ANALYTICS_EVENTS.SEGMENT_CREATED, athlete, { sport: "ride" }]]);
    });

    it("refuses a broken rule (422) with its code, and writes nothing", async () => {
      const athlete = await newAthlete();
      const response = await create(athlete, { sport: "run", name: "Trop court", points: northPath(lane(), 150) });
      expect(response.status).toBe(422);
      expect((await errorOf(response)).code).toBe("too_short");
      expect(await sql("select 1 from segments.segment where created_by = $1", [athlete])).toEqual([]);
      expect(capture).not.toHaveBeenCalled();
    });

    it("refuses a name of fewer than 3 characters once trimmed (422)", async () => {
      const athlete = await newAthlete();
      const response = await create(athlete, { sport: "run", name: "  ab  ", points: northPath(lane(), 1_000) });
      expect(response.status).toBe(422);
      expect((await errorOf(response)).code).toBe("validation_error");
    });

    it("refuses a duplicate of the same sport (409, with the existing Segment); allows a shorter one inside, or another sport", async () => {
      const first = await newAthlete();
      const second = await newAthlete();
      const lon = lane();
      const existing = await createOne(first, { name: "Le Semnoz", points: northPath(lon, 1_000) });

      // Drawn by someone else, with slightly different points: still the same Segment.
      const again = [at(lon, 0, 5), at(lon, 500, -5), at(lon, 1_000, 5)];
      const shown = (await (await preview(second, { sport: "run", points: again })).json()) as SegmentPreview;
      expect(shown.duplicate).toEqual({ id: existing.id, name: "Le Semnoz" });

      const refused = await create(second, { sport: "run", name: "Mon Semnoz", points: again });
      expect(refused.status).toBe(409);
      expect(await errorOf(refused)).toMatchObject({ code: "duplicate", existing: { id: existing.id, name: "Le Semnoz" } });

      await createOne(second, { name: "Le haut du Semnoz", points: northPath(lon, 1_000, 500) });
      await createOne(second, { sport: "hike", name: "Le Semnoz à pied", points: again });
    });

    it("allows 10 Segments per rolling 24 h (429 beyond, with Retry-After)", async () => {
      const athlete = await newAthlete();
      // Nine created in the last 24 h, one just before: they count but the oldest leaves the window first.
      for (let i = 0; i < 10; i++) {
        await sql(
          `insert into segments.segment (name, sport_type_code, created_by, created_at)
           values ('Ancien', 'run', $1, now() - make_interval(hours => $2))`,
          [athlete, i === 0 ? 23 : 1],
        );
      }
      const lon = lane();
      const shown = (await (await preview(athlete, { sport: "run", points: northPath(lon, 1_000) })).json()) as SegmentPreview;
      expect(shown.quotaLeft).toBe(0);

      const refused = await create(athlete, { sport: "run", name: "Un de trop", points: northPath(lon, 1_000) });
      expect(refused.status).toBe(429);
      expect((await errorOf(refused)).code).toBe("quota_reached");
      const retryAfterS = Number(refused.headers.get("retry-after"));
      expect(retryAfterS).toBeGreaterThan(3_500);
      expect(retryAfterS).toBeLessThanOrEqual(3_600);

      await sql("update segments.segment set created_at = now() - interval '25 hours' where created_by = $1 and created_at < now() - interval '22 hours'", [athlete]);
      await createOne(athlete, { name: "Enfin", points: northPath(lon, 1_000) });
    });
  });

  describe("PATCH /v1/segments/:id", () => {
    it("lets the creator rename it, nobody else (403)", async () => {
      const creator = await newAthlete();
      const other = await newAthlete();
      const created = await createOne(creator, { points: northPath(lane(), 1_000) });

      const renamed = await call(`/segments/${created.id}`, creator, { method: "PATCH", body: { name: " Nouveau nom " } });
      expect(renamed.status).toBe(200);
      expect(await renamed.json()).toEqual({ id: created.id, name: "Nouveau nom" });

      const refused = await call(`/segments/${created.id}`, other, { method: "PATCH", body: { name: "Le mien" } });
      expect(refused.status).toBe(403);
      expect((await errorOf(refused)).code).toBe("not_creator");
      expect((await call(`/segments/${created.id}`, creator, { method: "PATCH", body: { name: "ab" } })).status).toBe(422);
      expect((await call(`/segments/${randomUUID()}`, creator, { method: "PATCH", body: { name: "Nom" } })).status).toBe(404);
      expect(await sql("select name from segments.segment where id = $1", [created.id])).toEqual([{ name: "Nouveau nom" }]);
    });
  });

  describe("DELETE /v1/segments/:id", () => {
    it("deletes it for good with its Efforts and favourites while only its creator has Efforts", async () => {
      const creator = await newAthlete();
      const fan = await newAthlete();
      const created = await createOne(creator, { points: northPath(lane(), 1_000) });
      await seedEffort(creator, created.id, 300);
      expect((await call(`/segments/${created.id}/favorite`, fan, { method: "PUT" })).status).toBe(204);

      expect((await call(`/segments/${created.id}`, fan, { method: "DELETE" })).status).toBe(403);
      expect((await call(`/segments/${created.id}`, creator, { method: "DELETE" })).status).toBe(204);
      expect(await sql("select 1 from segments.segment where id = $1", [created.id])).toEqual([]);
      expect(await sql("select 1 from segments.segment_effort where segment_id = $1", [created.id])).toEqual([]);
      expect(await sql("select 1 from segments.segment_favorite where segment_id = $1", [created.id])).toEqual([]);
      expect((await call(`/segments/${created.id}`, creator, { method: "DELETE" })).status).toBe(404);
    });

    it("refuses once another athlete has an Effort on it (409 has_other_efforts)", async () => {
      const creator = await newAthlete();
      const other = await newAthlete();
      const created = await createOne(creator, { points: northPath(lane(), 1_000) });
      await seedEffort(other, created.id, 280, "rejected");

      const refused = await call(`/segments/${created.id}`, creator, { method: "DELETE" });
      expect(refused.status).toBe(409);
      expect((await errorOf(refused)).code).toBe("has_other_efforts");
      expect(await sql("select 1 from segments.segment where id = $1", [created.id])).toHaveLength(1);
    });
  });

  describe("favourites", () => {
    it("PUT and DELETE /v1/segments/:id/favorite are idempotent; 404 for an unknown Segment", async () => {
      const creator = await newAthlete();
      const fan = await newAthlete();
      const created = await createOne(creator, { points: northPath(lane(), 1_000) });
      const favorite = (method: string, id = created.id) => call(`/segments/${id}/favorite`, fan, { method });
      const stars = async () => sql("select 1 from segments.segment_favorite where segment_id = $1 and user_id = $2", [created.id, fan]);

      expect((await favorite("PUT")).status).toBe(204);
      expect((await favorite("PUT")).status).toBe(204);
      expect(await stars()).toHaveLength(1);
      expect((await favorite("DELETE")).status).toBe(204);
      expect((await favorite("DELETE")).status).toBe(204);
      expect(await stars()).toHaveLength(0);
      expect((await favorite("PUT", randomUUID())).status).toBe(404);
      expect((await favorite("DELETE", randomUUID())).status).toBe(404);
    });

    it("GET /v1/me/segment-favorites lists my stars, most recent first, by pages, with my best time", async () => {
      const creator = await newAthlete();
      const me = await newAthlete();
      const a = await createOne(creator, { name: "Segment A", points: northPath(lane(), 1_000) });
      const b = await createOne(creator, { sport: "ride", name: "Segment B", points: northPath(lane(), 1_000) });
      const c = await createOne(creator, { name: "Segment C", points: northPath(lane(), 1_000) });
      for (const segment of [a, b, c]) {
        expect((await call(`/segments/${segment.id}/favorite`, me, { method: "PUT" })).status).toBe(204);
      }
      await seedEffort(me, a.id, 320);
      await seedEffort(me, a.id, 300, "suspicious");
      await seedEffort(me, a.id, 200, "rejected");
      await seedEffort(creator, a.id, 100);

      const first = (await (await call("/me/segment-favorites?limit=2", me)).json()) as ListSegmentFavoritesResponse;
      expect(first.items.map((item) => item.name)).toEqual(["Segment C", "Segment B"]);
      expect(first.items[1]).toEqual({
        id: b.id,
        sport: "ride",
        name: "Segment B",
        verified: false,
        distanceM: 1_000,
        avgGradePct: 8,
        climbCategory: "4",
        myBestTimeS: null,
      });
      expect(first.nextCursor).not.toBeNull();

      const second = (await (
        await call(`/me/segment-favorites?limit=2&cursor=${first.nextCursor}`, me)
      ).json()) as ListSegmentFavoritesResponse;
      expect(second.items.map((item) => [item.name, item.myBestTimeS])).toEqual([["Segment A", 300]]);
      expect(second.nextCursor).toBeNull();
      expect((await call("/me/segment-favorites?cursor=nope", me)).status).toBe(422);
    });
  });
});
