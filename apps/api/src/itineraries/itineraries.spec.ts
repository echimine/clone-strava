import { randomUUID } from "node:crypto";
import { APP_FILTER, APP_INTERCEPTOR, APP_PIPE } from "@nestjs/core";
import { EventEmitterModule } from "@nestjs/event-emitter";
import type { NestExpressApplication } from "@nestjs/platform-express";
import { Test } from "@nestjs/testing";
import { ZodSerializerInterceptor, ZodValidationPipe } from "nestjs-zod";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { Itinerary, ListItinerariesResponse } from "@repo/contracts";
import { AnalyticsModule } from "@repo/core/analytics";
import { AuthService } from "@repo/core/auth";
import { ElevationModule } from "@repo/core/elevation";
import { CoreInfrastructureModule, DATABASE, type Database } from "@repo/core/infrastructure";
import { ItinerariesModule } from "@repo/core/itineraries";
import { decodePolyline, encodePolyline, type LonLat } from "@repo/geo";
import { ensureTestDatabaseMigrated, TEST_DATABASE_URL, TEST_REDIS_URL } from "../auth/test-auth-app.js";
import { SessionGuard } from "../auth/session.guard.js";
import { GlobalExceptionFilter } from "../common/global-exception.filter.js";
import { jsonBodyParser } from "../common/json-body.js";
import { ItinerariesController } from "./itineraries.controller.js";

/** Meters per degree of latitude on the haversine sphere (R = 6,371,000 m). */
const M_PER_DEG_LAT = (6_371_000 * Math.PI) / 180;

/** Climbs 100 m (500 → 600 m) from 45.90° N to 45.905° N, then flat. */
const terrain = ({ lat }: LonLat) => (lat <= 45.905 ? 500 + ((lat - 45.9) / 0.005) * 100 : 600);

const A = { lat: 45.9, lon: 6.12 };
const B = { lat: 45.91, lon: 6.12 };
const C = { lat: 45.92, lon: 6.12 };
const followAB = encodePolyline([A, { lat: 45.905, lon: 6.12 }, B], 6);
/** A → B follows a three-point path; B → C is a straight Leg. */
const geometry = { waypoints: [A, B, C], legs: [{ mode: "follow", polyline6: followAB }, { mode: "straight" }] };

/**
 * The lifecycle of `/v1/itineraries` (create, read, list, `PUT`, `PATCH`,
 * `DELETE`) over real HTTP (ADR-024 §2 integration tier, ADR-030 §5, §6):
 * real Nest, Postgres (migration 0006) and Redis from
 * `docker-compose.dev.yml`, sessions from `x-test-user`. Only the
 * `elevation` module's `fetch` is faked: IGN answers `terrain` south of
 * 46° N and has no data beyond, where Open-Meteo answers 1,000 m.
 */
describe("/v1/itineraries lifecycle (integration)", () => {
  let app: NestExpressApplication;
  let baseUrl: string;
  const athlete = randomUUID();
  const other = randomUUID();
  /** Owns only the Itineraries of the list test. */
  const lister = randomUUID();
  let elevationCalls = 0;
  let elevationDown = false;

  const fakeFetch = async (input: string | URL | Request, init?: RequestInit): Promise<Response> => {
    const url = new URL(input instanceof Request ? input.url : String(input));
    elevationCalls += 1;
    if (elevationDown) return new Response("Bad gateway", { status: 502 });
    if (url.hostname === "api.open-meteo.com") {
      // Open-Meteo answers a flat 1,000 m wherever IGN has no data.
      return Response.json({ elevation: url.searchParams.get("latitude")!.split(",").map(() => 1000) });
    }
    if (url.hostname !== "data.geopf.fr") throw new Error(`Unexpected request to ${url}`);
    const body = JSON.parse(String(init?.body)) as Record<string, string>;
    const lons = body.lon!.split("|").map(Number);
    const points = body.lat!.split("|").map((lat, i) => ({ lat: Number(lat), lon: lons[i]! }));
    // IGN covers nothing from 46° N.
    return Response.json({ elevations: points.map((point) => (point.lat >= 46 ? -99999 : terrain(point))) });
  };

  async function sql(text: string, params: unknown[] = []) {
    return (await app.get<Database>(DATABASE).$client.query(text, params)).rows;
  }

  function call(path: string, user: string | null, init: { method?: string; body?: unknown } = {}) {
    return fetch(`${baseUrl}/v1/itineraries${path}`, {
      method: init.method ?? "GET",
      headers: { "content-type": "application/json", ...(user ? { "x-test-user": user } : {}) },
      body: init.body === undefined ? undefined : JSON.stringify(init.body),
    });
  }

  function create(body: unknown, user: string | null = athlete) {
    return call("", user, { method: "POST", body });
  }

  function newItinerary(overrides: Record<string, unknown> = {}) {
    return { id: randomUUID(), name: "Tour du Semnoz", sportTypeCode: "hike", ...geometry, ...overrides };
  }

  async function createOne(user = athlete) {
    const response = await create(newItinerary(), user);
    expect(response.status).toBe(201);
    return (await response.json()) as Itinerary;
  }

  beforeAll(async () => {
    await ensureTestDatabaseMigrated();
    const moduleRef = await Test.createTestingModule({
      imports: [
        CoreInfrastructureModule.forRoot({ databaseUrl: TEST_DATABASE_URL, redisUrl: TEST_REDIS_URL }),
        AnalyticsModule.forRoot({}),
        EventEmitterModule.forRoot({ wildcard: true, delimiter: "." }),
        ElevationModule.forRoot({ fetch: fakeFetch as typeof fetch }),
        ItinerariesModule,
      ],
      controllers: [ItinerariesController],
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
    await app.listen(0);
    const address = app.getHttpServer().address();
    baseUrl = `http://127.0.0.1:${typeof address === "object" && address ? address.port : 0}`;
    for (const id of [athlete, other, lister]) {
      await sql('insert into "user" (id, name, email) values ($1, $2, $3)', [id, "Athlete", `${id}@test.local`]);
    }
  }, 30_000);

  afterAll(async () => {
    await sql('delete from "user" where id = any($1)', [[athlete, other, lister]]);
    await app?.close();
  });

  it("creates an Itinerary (201) and reads it back with its Waypoints, Legs and track", async () => {
    const body = newItinerary({ name: "  Tour du Semnoz  " });
    const response = await create(body);
    expect(response.status).toBe(201);
    const created = (await response.json()) as Itinerary;

    const read = await call(`/${body.id}`, athlete);
    expect(read.status).toBe(200);
    const itinerary = (await read.json()) as Itinerary;
    expect(itinerary).toEqual(created);
    expect(itinerary).toMatchObject({
      id: body.id,
      name: "Tour du Semnoz",
      sportTypeCode: "hike",
      waypoints: [A, B, C],
      distanceM: Math.round(0.02 * M_PER_DEG_LAT * 10) / 10,
      elevationGainM: 100,
      elevationSource: "ign",
    });
    expect(itinerary.legs).toEqual([
      { mode: "follow", polyline6: followAB },
      { mode: "straight", polyline6: encodePolyline([B, C], 6) },
    ]);
    expect(itinerary.createdAt).toBe(itinerary.updatedAt);
    // One point every 20 m from A (0 … 2,220 m) plus C itself, each with its altitude.
    const track = decodePolyline(itinerary.track.polyline6, 6);
    expect(track).toHaveLength(113);
    expect(itinerary.track.altitudesM).toHaveLength(track.length);
    expect(track[0]).toEqual(A);
    expect(track.at(-1)).toEqual(C);
    expect(itinerary.track.altitudesM[0]).toBe(500);
    expect(itinerary.track.altitudesM.at(-1)).toBe(600);
  });

  it("answers a replay by the same athlete with 200 and the stored Itinerary, writing nothing", async () => {
    const body = newItinerary();
    const created = (await (await create(body)).json()) as Itinerary;
    const callsBefore = elevationCalls;

    // Same id, different content: the replay neither recomputes nor overwrites.
    const replay = await create({ ...body, name: "Autre nom", waypoints: [A, B], legs: [{ mode: "straight" }] });
    expect(replay.status).toBe(200);
    expect(await replay.json()).toEqual(created);
    expect(elevationCalls).toBe(callsBefore);
    expect(await (await call(`/${body.id}`, athlete)).json()).toEqual(created);
  });

  it("answers 409 when the id belongs to another athlete", async () => {
    const body = newItinerary();
    expect((await create(body)).status).toBe(201);
    const response = await create(body, other);
    expect(response.status).toBe(409);
    expect(((await response.json()) as { error: { code: string } }).error.code).toBe("id_conflict");
  });

  it("answers 404, not 403, for another athlete's Itinerary, as for an unknown id", async () => {
    const body = newItinerary();
    expect((await create(body)).status).toBe(201);
    expect((await call(`/${body.id}`, other)).status).toBe(404);
    expect((await call(`/${randomUUID()}`, athlete)).status).toBe(404);
  });

  it("stores exactly what metrics-preview answers for the same Waypoints and Legs", async () => {
    const waypoints = [A, { lat: 45.9031, lon: 6.1243 }, { lat: 45.9112, lon: 6.1187 }];
    const legs = [{ mode: "straight" }, { mode: "straight" }];
    const preview = await call("/metrics-preview", athlete, { method: "POST", body: { waypoints, legs } });
    expect(preview.status).toBe(200);
    const metrics = await preview.json();

    const body = newItinerary({ waypoints, legs });
    expect((await create(body)).status).toBe(201);
    const stored = (await (await call(`/${body.id}`, athlete)).json()) as Itinerary;
    expect({ distanceM: stored.distanceM, elevationGainM: stored.elevationGainM, elevationSource: stored.elevationSource }).toEqual(
      metrics,
    );
  });

  describe("422 on an invalid save", () => {
    async function expectUnprocessable(overrides: Record<string, unknown>, field: string) {
      const callsBefore = elevationCalls;
      const response = await create(newItinerary(overrides));
      expect(response.status).toBe(422);
      const { error } = (await response.json()) as { error: { code: string; details: { field: string }[] } };
      expect(error.code).toBe("validation_error");
      expect(error.details.map((detail) => detail.field)).toContain(field);
      // Rejected before any elevation request.
      expect(elevationCalls).toBe(callsBefore);
    }

    it("rejects an empty name, once trimmed, and a name over 100 characters", async () => {
      await expectUnprocessable({ name: "   " }, "name");
      await expectUnprocessable({ name: "x".repeat(101) }, "name");
    });

    it("rejects a water sport and an unknown sport", async () => {
      await expectUnprocessable({ sportTypeCode: "swim" }, "sportTypeCode");
      await expectUnprocessable({ sportTypeCode: "skydiving" }, "sportTypeCode");
    });

    it("rejects a geometry that breaks an invariant of the computation", async () => {
      await expectUnprocessable({ legs: [{ mode: "straight" }] }, "legs");
    });

    it("stores nothing when the save is rejected", async () => {
      const body = newItinerary({ sportTypeCode: "swim" });
      expect((await create(body)).status).toBe(422);
      expect((await call(`/${body.id}`, athlete)).status).toBe(404);
    });

    it("answers 422, not 413, to a body over express's 100 kB default (POST and PUT)", async () => {
      // 60,000 decoded points (over the 50,000 limit): a ~120 kB polyline6.
      const tooLong = encodePolyline([A, ...Array.from({ length: 59_998 }, () => A), B], 6);
      const geometryOverLimit = { waypoints: [A, B], legs: [{ mode: "follow", polyline6: tooLong }] };
      expect(JSON.stringify(geometryOverLimit).length).toBeGreaterThan(100 * 1024);

      const posted = await create(newItinerary(geometryOverLimit));
      expect(posted.status).toBe(422);
      expect(((await posted.json()) as { error: { code: string } }).error.code).toBe("validation_error");

      const created = await createOne();
      const put = await call(`/${created.id}`, athlete, {
        method: "PUT",
        body: { name: created.name, sportTypeCode: "hike", ...geometryOverLimit },
      });
      expect(put.status).toBe(422);
      expect(await (await call(`/${created.id}`, athlete)).json()).toEqual(created);
    });
  });

  it("answers a retryable 503 and stores nothing when the elevation provider fails", async () => {
    const body = newItinerary();
    elevationDown = true;
    try {
      const response = await create(body);
      expect(response.status).toBe(503);
      expect(((await response.json()) as { error: { code: string } }).error.code).toBe("elevation_unavailable");
    } finally {
      elevationDown = false;
    }
    expect((await call(`/${body.id}`, athlete)).status).toBe(404);
  });

  describe("PUT /v1/itineraries/:id", () => {
    /** Beyond IGN's coverage in the fake: Open-Meteo answers 1,000 m everywhere. */
    const D = { lat: 46, lon: 6.12 };
    const E = { lat: 46.01, lon: 6.12 };
    const replacement = { name: "Crêt de Châtillon", sportTypeCode: "run", waypoints: [D, E], legs: [{ mode: "straight" }] };

    it("replaces name, sport, Waypoints and Legs and recomputes distance, gain and source", async () => {
      const created = await createOne();
      const response = await call(`/${created.id}`, athlete, { method: "PUT", body: replacement });
      expect(response.status).toBe(200);
      const updated = (await response.json()) as Itinerary;
      expect(updated).toMatchObject({
        id: created.id,
        name: "Crêt de Châtillon",
        sportTypeCode: "run",
        waypoints: [D, E],
        legs: [{ mode: "straight", polyline6: encodePolyline([D, E], 6) }],
        distanceM: Math.round(0.01 * M_PER_DEG_LAT * 10) / 10,
        elevationGainM: 0,
        elevationSource: "open_meteo",
        createdAt: created.createdAt,
      });
      expect(updated.track.altitudesM.every((altitude) => altitude === 1000)).toBe(true);
      expect(Date.parse(updated.updatedAt)).toBeGreaterThan(Date.parse(created.updatedAt));
      expect(await (await call(`/${created.id}`, athlete)).json()).toEqual(updated);
    });

    it("answers a retryable 503 and changes nothing when the elevation provider fails", async () => {
      const created = await createOne();
      elevationDown = true;
      try {
        const response = await call(`/${created.id}`, athlete, { method: "PUT", body: replacement });
        expect(response.status).toBe(503);
        expect(((await response.json()) as { error: { code: string } }).error.code).toBe("elevation_unavailable");
      } finally {
        elevationDown = false;
      }
      expect(await (await call(`/${created.id}`, athlete)).json()).toEqual(created);
    });

    it("answers 404 for another athlete's Itinerary or an unknown id, without computing or writing", async () => {
      const created = await createOne();
      const callsBefore = elevationCalls;
      expect((await call(`/${created.id}`, other, { method: "PUT", body: replacement })).status).toBe(404);
      expect((await call(`/${randomUUID()}`, athlete, { method: "PUT", body: replacement })).status).toBe(404);
      expect(elevationCalls).toBe(callsBefore);
      expect(await (await call(`/${created.id}`, athlete)).json()).toEqual(created);
    });

    it("rejects an invalid replacement with 422 and changes nothing", async () => {
      const created = await createOne();
      const response = await call(`/${created.id}`, athlete, { method: "PUT", body: { ...replacement, sportTypeCode: "swim" } });
      expect(response.status).toBe(422);
      expect(await (await call(`/${created.id}`, athlete)).json()).toEqual(created);
    });
  });

  describe("PATCH /v1/itineraries/:id", () => {
    it("renames the Itinerary and moves updated_at, without calling the elevation module", async () => {
      const created = await createOne();
      const callsBefore = elevationCalls;
      const response = await call(`/${created.id}`, athlete, { method: "PATCH", body: { name: "  Semnoz par les crêtes " } });
      expect(response.status).toBe(200);
      const renamed = (await response.json()) as Itinerary;
      expect(elevationCalls).toBe(callsBefore);
      expect(renamed).toEqual({ ...created, name: "Semnoz par les crêtes", updatedAt: renamed.updatedAt });
      expect(Date.parse(renamed.updatedAt)).toBeGreaterThan(Date.parse(created.updatedAt));
      expect(await (await call(`/${created.id}`, athlete)).json()).toEqual(renamed);
    });

    it("rejects an empty name, once trimmed, and a name over 100 characters", async () => {
      const created = await createOne();
      for (const name of ["   ", "x".repeat(101)]) {
        expect((await call(`/${created.id}`, athlete, { method: "PATCH", body: { name } })).status).toBe(422);
      }
      expect(await (await call(`/${created.id}`, athlete)).json()).toEqual(created);
    });

    it("answers 404 for another athlete's Itinerary or an unknown id", async () => {
      const created = await createOne();
      expect((await call(`/${created.id}`, other, { method: "PATCH", body: { name: "Volé" } })).status).toBe(404);
      expect((await call(`/${randomUUID()}`, athlete, { method: "PATCH", body: { name: "Volé" } })).status).toBe(404);
      expect(await (await call(`/${created.id}`, athlete)).json()).toEqual(created);
    });
  });

  describe("DELETE /v1/itineraries/:id", () => {
    it("answers 204 with no body, then the Itinerary is gone", async () => {
      const created = await createOne();
      const response = await call(`/${created.id}`, athlete, { method: "DELETE" });
      expect(response.status).toBe(204);
      expect(await response.text()).toBe("");
      expect((await call(`/${created.id}`, athlete)).status).toBe(404);
      expect((await call(`/${created.id}`, athlete, { method: "DELETE" })).status).toBe(404);
    });

    it("answers 404 for another athlete's Itinerary, and keeps it", async () => {
      const created = await createOne();
      expect((await call(`/${created.id}`, other, { method: "DELETE" })).status).toBe(404);
      expect((await call(`/${created.id}`, athlete)).status).toBe(200);
    });
  });

  it("deletes a user's Itineraries, Waypoints and Legs with the account", async () => {
    const leaving = randomUUID();
    await sql('insert into "user" (id, name, email) values ($1, $2, $3)', [leaving, "Leaving", `${leaving}@test.local`]);
    const { id } = await createOne(leaving);
    await sql('delete from "user" where id = $1', [leaving]);
    const [counts] = await sql(
      `select (select count(*) from itineraries.itinerary where id = $1)::int as itineraries,
              (select count(*) from itineraries.itinerary_waypoint where itinerary_id = $1)::int as waypoints,
              (select count(*) from itineraries.itinerary_leg where itinerary_id = $1)::int as legs`,
      [id],
    );
    expect(counts).toEqual({ itineraries: 0, waypoints: 0, legs: 0 });
  });

  describe("GET /v1/itineraries", () => {
    const ids: string[] = [];

    beforeAll(async () => {
      for (let i = 0; i < 5; i++) {
        const body = newItinerary({ name: `Itinéraire ${i}` });
        expect((await create(body, lister)).status).toBe(201);
        ids.push(body.id);
      }
      // Four of them updated within the same millisecond, two at the very same microsecond.
      const updatedAt = [
        "2026-10-01T10:00:00.000300Z",
        "2026-10-01T10:00:00.000100Z",
        "2026-10-01T10:00:00.000200Z",
        "2026-10-01T10:00:00.000200Z",
        "2026-10-01T09:00:00.000000Z",
      ];
      for (const [i, id] of ids.entries()) {
        await sql("update itineraries.itinerary set updated_at = $2 where id = $1", [id, updatedAt[i]]);
      }
    });

    async function list(query: string, user = lister) {
      const response = await call(query, user);
      expect(response.status).toBe(200);
      return (await response.json()) as ListItinerariesResponse;
    }

    it("lists the athlete's Itineraries, most recently updated first, page by page with a cursor", async () => {
      const [i0, i1, i2, i3, i4] = ids as [string, string, string, string, string];
      const [tieFirst, tieSecond] = [i2, i3].sort();
      const first = await list("?limit=2");
      expect(first.items.map((item) => item.id)).toEqual([i0, tieFirst]);
      expect(first.nextCursor).not.toBeNull();
      const second = await list(`?limit=2&cursor=${first.nextCursor}`);
      expect(second.items.map((item) => item.id)).toEqual([tieSecond, i1]);
      const third = await list(`?limit=2&cursor=${second.nextCursor}`);
      expect(third.items.map((item) => item.id)).toEqual([i4]);
      expect(third.nextCursor).toBeNull();
    });

    it("gives each item its name, sport, distance, gain, map polyline and update time", async () => {
      const { items } = await list("?limit=1");
      expect(items).toEqual([
        {
          id: ids[0],
          name: "Itinéraire 0",
          sportTypeCode: "hike",
          distanceM: Math.round(0.02 * M_PER_DEG_LAT * 10) / 10,
          elevationGainM: 100,
          mapPolyline: expect.any(String),
          updatedAt: "2026-10-01T10:00:00.000Z",
        },
      ]);
      // A straight meridian line: simplified down to its two ends, in polyline5.
      expect(decodePolyline(items[0]!.mapPolyline, 5)).toEqual([A, C]);
    });

    it("shows an athlete only their own Itineraries", async () => {
      const othersList = await list("?limit=50", other);
      expect(othersList.items.some((item) => ids.includes(item.id))).toBe(false);
    });

    it("rejects an invalid cursor with 422", async () => {
      const response = await call("?cursor=garbage", lister);
      expect(response.status).toBe(422);
      expect(((await response.json()) as { error: { code: string } }).error.code).toBe("invalid_cursor");
    });
  });

  it("requires a session", async () => {
    expect((await create(newItinerary(), null)).status).toBe(401);
    expect((await call("", null)).status).toBe(401);
  });
});
