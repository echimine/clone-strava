import { randomUUID } from "node:crypto";
import { APP_FILTER, APP_INTERCEPTOR, APP_PIPE } from "@nestjs/core";
import { EventEmitter2, EventEmitterModule } from "@nestjs/event-emitter";
import type { NestExpressApplication } from "@nestjs/platform-express";
import { Test } from "@nestjs/testing";
import { Redis } from "ioredis";
import { ZodSerializerInterceptor, ZodValidationPipe } from "nestjs-zod";
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi, type MockInstance } from "vitest";
import { ITINERARY_DELETED_EVENT, ITINERARY_SAVED_EVENT, type Itinerary } from "@repo/contracts";
import { AnalyticsModule, AnalyticsService } from "@repo/core/analytics";
import { AuthService } from "@repo/core/auth";
import { ElevationModule } from "@repo/core/elevation";
import { CoreInfrastructureModule, DATABASE, type Database } from "@repo/core/infrastructure";
import { ItinerariesModule } from "@repo/core/itineraries";
import { RealtimeBridgeModule } from "@repo/core/realtime";
import { encodePolyline, type LonLat } from "@repo/geo";
import {
  createRedisEventSource,
  ITINERARY_DELETED,
  ITINERARY_SAVED,
  userTopic,
  type RealtimeChannelMessage,
  type RealtimeEventSource,
} from "@repo/realtime";
import { ensureTestDatabaseMigrated, TEST_DATABASE_URL, TEST_REDIS_URL } from "../auth/test-auth-app.js";
import { SessionGuard } from "../auth/session.guard.js";
import { GlobalExceptionFilter } from "../common/global-exception.filter.js";
import { jsonBodyParser } from "../common/json-body.js";
import { ItinerariesController } from "./itineraries.controller.js";

/** Climbs 100 m (500 → 600 m) from 45.90° N to 45.905° N, then flat. */
const terrain = ({ lat }: LonLat) => (lat <= 45.905 ? 500 + ((lat - 45.9) / 0.005) * 100 : 600);

const A = { lat: 45.9, lon: 6.12 };
const B = { lat: 45.91, lon: 6.12 };
const C = { lat: 45.92, lon: 6.12 };
const followAB = encodePolyline([A, { lat: 45.905, lon: 6.12 }, B], 6);
/** ~2.2 km, 100 m of gain, one of its two Legs straight. */
const geometry = { waypoints: [A, B, C], legs: [{ mode: "follow", polyline6: followAB }, { mode: "straight" }] };

/**
 * Lifecycle events of the Itineraries (ADR-030 §9, §10) over real HTTP,
 * Postgres and Redis: domain events after commit, their realtime relay on
 * `user:{id}` (read back from the Redis channel the gateways listen to),
 * and the PostHog events (`AnalyticsService.capture` spied on). Only the
 * `elevation` module's `fetch` is faked.
 */
describe("/v1/itineraries lifecycle events (integration)", () => {
  let app: NestExpressApplication;
  let baseUrl: string;
  let source: RealtimeEventSource;
  const received: RealtimeChannelMessage[] = [];
  let capture: MockInstance<AnalyticsService["capture"]>;
  let emit: MockInstance<EventEmitter2["emit"]>;
  const athlete = randomUUID();
  const other = randomUUID();
  let elevationDown = false;

  const fakeFetch = async (input: string | URL | Request, init?: RequestInit): Promise<Response> => {
    const url = new URL(input instanceof Request ? input.url : String(input));
    if (elevationDown) return new Response("Bad gateway", { status: 502 });
    if (url.hostname !== "data.geopf.fr") throw new Error(`Unexpected request to ${url}`);
    const body = JSON.parse(String(init?.body)) as Record<string, string>;
    const lons = body.lon!.split("|").map(Number);
    return Response.json({
      elevations: body.lat!.split("|").map((lat, i) => terrain({ lat: Number(lat), lon: lons[i]! })),
    });
  };

  async function sql(text: string, params: unknown[] = []) {
    return (await app.get<Database>(DATABASE).$client.query(text, params)).rows;
  }

  function call(path: string, user: string, init: { method?: string; body?: unknown } = {}) {
    return fetch(`${baseUrl}/v1/itineraries${path}`, {
      method: init.method ?? "GET",
      headers: { "content-type": "application/json", "x-test-user": user },
      body: init.body === undefined ? undefined : JSON.stringify(init.body),
    });
  }

  function newItinerary(overrides: Record<string, unknown> = {}) {
    return { id: randomUUID(), name: "Tour du Semnoz", sportTypeCode: "hike", ...geometry, ...overrides };
  }

  async function createOne(body = newItinerary()) {
    const response = await call("", athlete, { method: "POST", body });
    expect(response.status).toBe(201);
    return (await response.json()) as Itinerary;
  }

  /** Realtime messages about one Itinerary (other spec files publish on the same channel). */
  function messagesAbout(itineraryId: string) {
    return received.filter((message) => message.envelope.data.itineraryId === itineraryId);
  }

  async function waitForMessages(itineraryId: string, count: number) {
    await vi.waitFor(() => expect(messagesAbout(itineraryId).length).toBeGreaterThanOrEqual(count), {
      timeout: 3_000,
    });
    return messagesAbout(itineraryId);
  }

  /** Lets an event that should not come a chance to arrive. */
  const settle = () => new Promise((resolve) => setTimeout(resolve, 200));

  function emitted(name: string) {
    return emit.mock.calls.filter(([event]) => event === name).map(([, payload]) => payload);
  }

  beforeAll(async () => {
    await ensureTestDatabaseMigrated();
    const moduleRef = await Test.createTestingModule({
      imports: [
        CoreInfrastructureModule.forRoot({ databaseUrl: TEST_DATABASE_URL, redisUrl: TEST_REDIS_URL }),
        AnalyticsModule.forRoot({}),
        EventEmitterModule.forRoot({ wildcard: true, delimiter: "." }),
        RealtimeBridgeModule,
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
    for (const id of [athlete, other]) {
      await sql('insert into "user" (id, name, email) values ($1, $2, $3)', [id, "Athlete", `${id}@test.local`]);
    }

    source = createRedisEventSource(new Redis(TEST_REDIS_URL));
    source.onMessage((message) => received.push(message));
    await source.subscribe();
    capture = vi.spyOn(app.get(AnalyticsService), "capture");
    emit = vi.spyOn(app.get(EventEmitter2), "emit");
  }, 30_000);

  beforeEach(() => {
    elevationDown = false;
    capture.mockClear();
    emit.mockClear();
  });

  afterAll(async () => {
    await source?.close();
    await sql('delete from "user" where id = any($1)', [[athlete, other]]);
    await app?.close();
  });

  it("on creation, relays itinerary.saved to the athlete only and captures itinerary_created", async () => {
    const itinerary = await createOne();

    expect(emitted(ITINERARY_SAVED_EVENT)).toEqual([
      { itineraryId: itinerary.id, userId: athlete, updatedAt: itinerary.updatedAt },
    ]);
    const [message] = await waitForMessages(itinerary.id, 1);
    expect(message!.topics).toEqual([userTopic(athlete)]);
    expect(message!.envelope.t).toBe(ITINERARY_SAVED);
    expect(message!.envelope.data).toEqual({ itineraryId: itinerary.id, updatedAt: itinerary.updatedAt });

    // Rounded figures, no coordinates (catalog of #20).
    expect(capture.mock.calls).toEqual([
      [
        "itinerary_created",
        athlete,
        {
          itineraryId: itinerary.id,
          sportTypeCode: "hike",
          sportCategory: "foot",
          waypointCount: 3,
          straightLegRatio: 0.5,
          distanceKm: 2,
          elevationGainM: 100,
          elevationSource: "ign",
        },
      ],
    ]);
  });

  it("emits nothing when a POST is replayed", async () => {
    const body = newItinerary();
    await createOne(body);
    await waitForMessages(body.id, 1);
    capture.mockClear();
    emit.mockClear();

    const replay = await call("", athlete, { method: "POST", body });

    expect(replay.status).toBe(200);
    await settle();
    expect(emitted(ITINERARY_SAVED_EVENT)).toEqual([]);
    expect(capture).not.toHaveBeenCalled();
    expect(messagesAbout(body.id)).toHaveLength(1);
  });

  it("emits nothing when the transaction fails", async () => {
    const ghost = randomUUID(); // No `user` row: the insert breaks its foreign key.
    const body = newItinerary();

    const response = await call("", ghost, { method: "POST", body });

    expect(response.status).toBe(500);
    await settle();
    expect(emitted(ITINERARY_SAVED_EVENT)).toEqual([]);
    expect(capture).not.toHaveBeenCalled();
    expect(messagesAbout(body.id)).toEqual([]);
  });

  it("on a full update, relays itinerary.saved and captures itinerary_updated", async () => {
    const itinerary = await createOne();
    await waitForMessages(itinerary.id, 1);
    capture.mockClear();

    const response = await call(`/${itinerary.id}`, athlete, {
      method: "PUT",
      body: { name: "Semnoz à vélo", sportTypeCode: "ride", ...geometry },
    });
    expect(response.status).toBe(200);
    const updated = (await response.json()) as Itinerary;

    const messages = await waitForMessages(itinerary.id, 2);
    expect(messages[1]!.topics).toEqual([userTopic(athlete)]);
    expect(messages[1]!.envelope).toMatchObject({
      t: ITINERARY_SAVED,
      data: { itineraryId: itinerary.id, updatedAt: updated.updatedAt },
    });
    expect(capture).toHaveBeenCalledExactlyOnceWith("itinerary_updated", athlete, {
      itineraryId: itinerary.id,
      sportTypeCode: "ride",
      sportCategory: "wheels",
      waypointCount: 3,
      straightLegRatio: 0.5,
      distanceKm: 2,
      elevationGainM: 100,
      elevationSource: "ign",
    });
  });

  it("on a rename, relays itinerary.saved and captures itinerary_renamed", async () => {
    const itinerary = await createOne();
    await waitForMessages(itinerary.id, 1);
    capture.mockClear();

    const response = await call(`/${itinerary.id}`, athlete, { method: "PATCH", body: { name: "Semnoz" } });
    const renamed = (await response.json()) as Itinerary;

    const messages = await waitForMessages(itinerary.id, 2);
    expect(messages[1]!.topics).toEqual([userTopic(athlete)]);
    expect(messages[1]!.envelope).toMatchObject({
      t: ITINERARY_SAVED,
      data: { itineraryId: itinerary.id, updatedAt: renamed.updatedAt },
    });
    expect(capture.mock.calls).toEqual([["itinerary_renamed", athlete, { itineraryId: itinerary.id }]]);
  });

  it("on a delete, relays itinerary.deleted and captures itinerary_deleted", async () => {
    const itinerary = await createOne();
    await waitForMessages(itinerary.id, 1);
    capture.mockClear();

    expect((await call(`/${itinerary.id}`, athlete, { method: "DELETE" })).status).toBe(204);

    expect(emitted(ITINERARY_DELETED_EVENT)).toEqual([{ itineraryId: itinerary.id, userId: athlete }]);
    const messages = await waitForMessages(itinerary.id, 2);
    expect(messages[1]!.topics).toEqual([userTopic(athlete)]);
    expect(messages[1]!.envelope).toMatchObject({ t: ITINERARY_DELETED, data: { itineraryId: itinerary.id } });
    expect(capture.mock.calls).toEqual([["itinerary_deleted", athlete, { itineraryId: itinerary.id }]]);
  });

  it("emits nothing when someone else's Itinerary is targeted (404)", async () => {
    const itinerary = await createOne();
    await waitForMessages(itinerary.id, 1);
    capture.mockClear();
    emit.mockClear();

    expect((await call(`/${itinerary.id}`, other, { method: "PATCH", body: { name: "Mine" } })).status).toBe(404);
    expect((await call(`/${itinerary.id}`, other, { method: "DELETE" })).status).toBe(404);

    await settle();
    expect(emit).not.toHaveBeenCalled();
    expect(capture).not.toHaveBeenCalled();
    expect(messagesAbout(itinerary.id)).toHaveLength(1);
  });

  it("captures itinerary_save_failed on a 503, and emits no domain event", async () => {
    const itinerary = await createOne();
    capture.mockClear();
    emit.mockClear();
    elevationDown = true;

    const created = await call("", athlete, { method: "POST", body: newItinerary() });
    const updated = await call(`/${itinerary.id}`, athlete, { method: "PUT", body: { name: "Semnoz", sportTypeCode: "hike", ...geometry } });

    expect(created.status).toBe(503);
    expect(updated.status).toBe(503);
    expect(capture.mock.calls).toEqual([
      ["itinerary_save_failed", athlete, { errorCode: "elevation_unavailable" }],
      ["itinerary_save_failed", athlete, { errorCode: "elevation_unavailable" }],
    ]);
    expect(emit).not.toHaveBeenCalled();
  });
});
