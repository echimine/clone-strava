import { randomUUID } from "node:crypto";
import { APP_FILTER, APP_INTERCEPTOR, APP_PIPE } from "@nestjs/core";
import type { NestExpressApplication } from "@nestjs/platform-express";
import { Test } from "@nestjs/testing";
import express from "express";
import { ZodSerializerInterceptor, ZodValidationPipe } from "nestjs-zod";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import type { ItineraryMetrics } from "@repo/contracts";
import { AuthService } from "@repo/core/auth";
import { ElevationModule } from "@repo/core/elevation";
import { CoreInfrastructureModule, DATABASE, type Database } from "@repo/core/infrastructure";
import { ItinerariesModule } from "@repo/core/itineraries";
import { encodePolyline, type LonLat } from "@repo/geo";
import { ensureTestDatabaseMigrated, TEST_DATABASE_URL, TEST_REDIS_URL } from "../auth/test-auth-app.js";
import { SessionGuard } from "../auth/session.guard.js";
import { GlobalExceptionFilter } from "../common/global-exception.filter.js";
import { JSON_BODY_LIMIT } from "../common/json-body.js";
import { ItinerariesController } from "./itineraries.controller.js";

/** Meters per degree of latitude on the haversine sphere (R = 6,371,000 m). */
const M_PER_DEG_LAT = (6_371_000 * Math.PI) / 180;

/** Altitude served by the fake providers for a point. */
type Terrain = (point: LonLat) => number;
/** Whether a point is inside IGN coverage; outside, IGN answers `-99999`. */
type Coverage = (point: LonLat) => boolean;
const everywhere: Coverage = () => true;

/**
 * Along the meridian 6.12° E from 45.90° N: climbs 100 m (500 → 600 m)
 * over ~556 m, then a plateau with sub-meter noise (always below 600 m, so
 * it never adds gain), then a 50 m descent to 45.92° N.
 */
const hillTerrain: Terrain = ({ lat }) => {
  if (lat <= 45.905) return 500 + ((lat - 45.9) / 0.005) * 100;
  if (lat <= 45.915) return 600 - 0.8 * (Math.round(lat * 1e4) % 2);
  return 600 - ((lat - 45.915) / 0.005) * 50;
};

const A = { lat: 45.9, lon: 6.12 };
const B = { lat: 45.91, lon: 6.12 };
const C = { lat: 45.92, lon: 6.12 };
/** A → B follows a (straight, three-point) path; B → C is a straight Leg. */
const hillBody = {
  waypoints: [A, B, C],
  legs: [{ mode: "follow", polyline6: encodePolyline([A, { lat: 45.905, lon: 6.12 }, B], 6) }, { mode: "straight" }],
};

/**
 * `POST /v1/itineraries/metrics-preview` over real HTTP (ADR-024 §2
 * integration tier, ADR-030 §3, §6): real Nest, Postgres and Redis from
 * `docker-compose.dev.yml`, sessions from `x-test-user`. Only the
 * `elevation` module's `fetch` is faked: it plays IGN and Open-Meteo.
 */
describe("POST /v1/itineraries/metrics-preview (integration)", () => {
  let app: NestExpressApplication;
  let baseUrl: string;
  const athlete = randomUUID();

  let terrain: Terrain = hillTerrain;
  let ignCoverage: Coverage = everywhere;
  let failure: { provider: "ign" | "open_meteo"; response: () => Response | Promise<never> } | null = null;
  const calls = { ign: [] as LonLat[][], openMeteo: [] as LonLat[][] };

  const fakeFetch = async (input: string | URL | Request, init?: RequestInit): Promise<Response> => {
    const url = new URL(input instanceof Request ? input.url : String(input));
    if (url.hostname === "data.geopf.fr") {
      if (failure?.provider === "ign") return failure.response();
      const body = JSON.parse(String(init?.body)) as Record<string, string>;
      expect(init?.method).toBe("POST");
      expect(body).toMatchObject({ resource: "ign_rge_alti_wld", delimiter: "|", zonly: "true" });
      const lons = body.lon!.split("|").map(Number);
      const points = body.lat!.split("|").map((lat, i) => ({ lat: Number(lat), lon: lons[i]! }));
      calls.ign.push(points);
      return Response.json({ elevations: points.map((point) => (ignCoverage(point) ? terrain(point) : -99999)) });
    }
    if (url.hostname === "api.open-meteo.com") {
      if (failure?.provider === "open_meteo") return failure.response();
      const lons = url.searchParams.get("longitude")!.split(",").map(Number);
      const points = url.searchParams.get("latitude")!.split(",").map((lat, i) => ({ lat: Number(lat), lon: lons[i]! }));
      calls.openMeteo.push(points);
      return Response.json({ elevation: points.map((point) => terrain(point)) });
    }
    throw new Error(`Unexpected request to ${url}`);
  };

  async function sql(text: string, params: unknown[] = []) {
    return (await app.get<Database>(DATABASE).$client.query(text, params)).rows;
  }

  function preview(body: unknown, user: string | null = athlete) {
    return fetch(`${baseUrl}/v1/itineraries/metrics-preview`, {
      method: "POST",
      headers: { "content-type": "application/json", ...(user ? { "x-test-user": user } : {}) },
      body: JSON.stringify(body),
    });
  }

  async function expectUnprocessable(body: unknown) {
    const response = await preview(body);
    expect(response.status).toBe(422);
    expect(((await response.json()) as { error: { code: string } }).error.code).toBe("validation_error");
  }

  beforeAll(async () => {
    await ensureTestDatabaseMigrated();
    const moduleRef = await Test.createTestingModule({
      imports: [
        CoreInfrastructureModule.forRoot({ databaseUrl: TEST_DATABASE_URL, redisUrl: TEST_REDIS_URL }),
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

    // Same JSON body parser as `main.ts`: a long Itinerary exceeds express's 100 kB default.
    app = moduleRef.createNestApplication<NestExpressApplication>({ bodyParser: false });
    app.use(express.json({ limit: JSON_BODY_LIMIT }));
    app.setGlobalPrefix("v1");
    await app.listen(0);
    const address = app.getHttpServer().address();
    baseUrl = `http://127.0.0.1:${typeof address === "object" && address ? address.port : 0}`;
    await sql('insert into "user" (id, name, email) values ($1, $2, $3)', [athlete, "Athlete", `${athlete}@test.local`]);
  }, 30_000);

  beforeEach(() => {
    terrain = hillTerrain;
    ignCoverage = everywhere;
    failure = null;
    calls.ign = [];
    calls.openMeteo = [];
  });

  afterAll(async () => {
    await sql('delete from "user" where id = $1', [athlete]);
    await app?.close();
  });

  it("measures an all-IGN Itinerary: distance on the 2D track, gain with hysteresis on ~20 m points", async () => {
    const response = await preview(hillBody);
    expect(response.status).toBe(200);
    const body = (await response.json()) as ItineraryMetrics;
    expect(body).toEqual({
      // 0.02° of latitude along a meridian, rounded to the decimeter.
      distanceM: Math.round(0.02 * M_PER_DEG_LAT * 10) / 10,
      // The 100 m climb; the plateau noise stays under the 2 m hysteresis.
      elevationGainM: 100,
      elevationSource: "ign",
    });
    // One point every 20 m from A (0 … 2,220 m) plus C itself: 113 points, one IGN request.
    expect(calls.ign.map((points) => points.length)).toEqual([113]);
    expect(calls.ign[0]![0]).toEqual(A);
    expect(calls.ign[0]!.at(-1)).toEqual(C);
    expect(calls.openMeteo).toEqual([]);
  });

  it("falls back to Open-Meteo for every point outside IGN coverage (open_meteo), 100 points per request", async () => {
    ignCoverage = () => false;
    const response = await preview(hillBody);
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ elevationGainM: 100, elevationSource: "open_meteo" });
    expect(calls.openMeteo.map((points) => points.length)).toEqual([100, 13]);
  });

  it("mixes sources when only part of the track is covered by IGN (mixed)", async () => {
    // IGN has no data north of 45.915° N (the descent); Open-Meteo has it all.
    ignCoverage = (point) => point.lat <= 45.915;
    const response = await preview(hillBody);
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ elevationGainM: 100, elevationSource: "mixed" });
    expect(calls.openMeteo.flat().length).toBeGreaterThan(0);
    expect(calls.openMeteo.flat().every((point) => point.lat > 45.915)).toBe(true);
  });

  it("splits IGN requests at 5,000 points", async () => {
    terrain = () => 300;
    const north = { lat: 46.98, lon: 6.12 };
    const response = await preview({ waypoints: [A, north], legs: [{ mode: "straight" }] });
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({
      distanceM: Math.round(1.08 * M_PER_DEG_LAT * 10) / 10,
      elevationGainM: 0,
      elevationSource: "ign",
    });
    const sizes = calls.ign.map((points) => points.length);
    expect(sizes).toHaveLength(2);
    expect(sizes[0]).toBe(5000);
    expect(sizes[0]! + sizes[1]!).toBe(Math.floor((1.08 * M_PER_DEG_LAT) / 20) + 2);
  });

  describe("422 when an invariant is violated", () => {
    it("rejects a Leg count other than Waypoints − 1", async () => {
      await expectUnprocessable({ waypoints: [A, B, C], legs: [{ mode: "straight" }] });
    });

    it("rejects fewer than 2 and more than 200 Waypoints", async () => {
      await expectUnprocessable({ waypoints: [A], legs: [] });
      const waypoints = Array.from({ length: 201 }, (_, i) => ({ lat: 45.9 + i * 0.0001, lon: 6.12 }));
      await expectUnprocessable({ waypoints, legs: waypoints.slice(1).map(() => ({ mode: "straight" })) });
    });

    it("rejects more than 50,000 decoded points", async () => {
      const path = [A, ...Array.from({ length: 49_999 }, () => A), B];
      await expectUnprocessable({ waypoints: [A, B], legs: [{ mode: "follow", polyline6: encodePolyline(path, 6) }] });
    });

    it("rejects an Itinerary longer than 1,000 km", async () => {
      await expectUnprocessable({ waypoints: [A, { lat: 55, lon: 6.12 }], legs: [{ mode: "straight" }] });
    });

    it("rejects a follow Leg whose start or end is more than 30 m from its Waypoint", async () => {
      // 0.0004° of latitude ≈ 44 m.
      const offStart = encodePolyline([{ lat: 45.8996, lon: 6.12 }, B], 6);
      await expectUnprocessable({ waypoints: [A, B], legs: [{ mode: "follow", polyline6: offStart }] });
      const offEnd = encodePolyline([A, { lat: 45.9104, lon: 6.12 }], 6);
      await expectUnprocessable({ waypoints: [A, B], legs: [{ mode: "follow", polyline6: offEnd }] });
    });

    it("rejects a malformed polyline6", async () => {
      await expectUnprocessable({ waypoints: [A, B], legs: [{ mode: "follow", polyline6: "_izlhA~" }] });
    });

    it("asks no elevation provider for an invalid body", async () => {
      await expectUnprocessable({ waypoints: [A, { lat: 55, lon: 6.12 }], legs: [{ mode: "straight" }] });
      expect(calls).toEqual({ ign: [], openMeteo: [] });
    });
  });

  describe("503 (retryable) when an elevation provider fails", () => {
    async function expectUnavailable() {
      const response = await preview(hillBody);
      expect(response.status).toBe(503);
      expect(((await response.json()) as { error: { code: string } }).error.code).toBe("elevation_unavailable");
      return response;
    }

    it("on an IGN outage", async () => {
      failure = { provider: "ign", response: () => new Response("Bad gateway", { status: 502 }) };
      await expectUnavailable();
      failure = { provider: "ign", response: () => Promise.reject(new TypeError("fetch failed")) };
      await expectUnavailable();
    });

    it("on an IGN 429, forwarding its Retry-After", async () => {
      failure = { provider: "ign", response: () => new Response("", { status: 429, headers: { "retry-after": "7" } }) };
      const response = await expectUnavailable();
      expect(response.headers.get("retry-after")).toBe("7");
    });

    it("on an Open-Meteo failure", async () => {
      ignCoverage = () => false;
      failure = { provider: "open_meteo", response: () => new Response("", { status: 429 }) };
      await expectUnavailable();
    });
  });

  it("requires a session", async () => {
    expect((await preview(hillBody, null)).status).toBe(401);
  });

  it("writes nothing for the athlete", async () => {
    expect((await preview(hillBody)).status).toBe(200);
    // Every athlete-owned table of the `itineraries` schema stays empty for them.
    const tables = await sql(
      `select table_name from information_schema.columns where table_schema = 'itineraries' and column_name = 'user_id'`,
    );
    for (const { table_name } of tables as { table_name: string }[]) {
      expect(await sql(`select 1 from itineraries."${table_name}" where user_id = $1`, [athlete])).toEqual([]);
    }
  });
});
