import { EventEmitter } from "node:events";
import { describe, expect, it, vi } from "vitest";
import { REALTIME_CHANNEL, realtimeChannelMessageSchema } from "./channel.js";
import { ACTIVITY_PROCESSED } from "./events.js";
import { PROTOCOL_VERSION } from "./protocol.js";
import {
  createRealtimePublisher,
  createRedisEventSource,
  type RealtimeEventPublisherRedis,
  type RealtimeEventSourceRedis,
} from "./publisher.js";

/** Fake `ioredis` publish-only connection. */
function createFakePublisherRedis(): RealtimeEventPublisherRedis & {
  publish: ReturnType<typeof vi.fn>;
} {
  return { publish: vi.fn().mockResolvedValue(1) };
}

/** Fake `ioredis` subscriber connection, driven through a plain EventEmitter. */
function createFakeSubscriberRedis(): RealtimeEventSourceRedis & {
  emitter: EventEmitter;
  subscribe: ReturnType<typeof vi.fn>;
  unsubscribe: ReturnType<typeof vi.fn>;
  quit: ReturnType<typeof vi.fn>;
} {
  const emitter = new EventEmitter();
  return {
    emitter,
    subscribe: vi.fn().mockResolvedValue(1),
    unsubscribe: vi.fn().mockResolvedValue(1),
    quit: vi.fn().mockResolvedValue("OK"),
    on: (event: string, listener: (...args: unknown[]) => void) => {
      emitter.on(event, listener);
      return emitter as unknown as ReturnType<RealtimeEventSourceRedis["on"]>;
    },
    off: (event: string, listener: (...args: unknown[]) => void) => {
      emitter.off(event, listener);
      return emitter as unknown as ReturnType<RealtimeEventSourceRedis["off"]>;
    },
  } as unknown as RealtimeEventSourceRedis & {
    emitter: EventEmitter;
    subscribe: ReturnType<typeof vi.fn>;
    unsubscribe: ReturnType<typeof vi.fn>;
    quit: ReturnType<typeof vi.fn>;
  };
}

describe("createRealtimePublisher", () => {
  it("builds an envelope and publishes it as JSON on the realtime channel", async () => {
    const redis = createFakePublisherRedis();
    const { publishRealtimeEvent } = createRealtimePublisher(redis);

    await publishRealtimeEvent(["user:1"], ACTIVITY_PROCESSED, {
      activityId: "act_1",
      status: "processed",
      at: "2026-09-24T10:00:00Z",
    });

    expect(redis.publish).toHaveBeenCalledTimes(1);
    const [channel, raw] = redis.publish.mock.calls[0] as [string, string];
    expect(channel).toBe(REALTIME_CHANNEL);

    const message = realtimeChannelMessageSchema.parse(JSON.parse(raw));
    expect(message.topics).toEqual(["user:1"]);
    expect(message.envelope.v).toBe(PROTOCOL_VERSION);
    expect(message.envelope.t).toBe(ACTIVITY_PROCESSED);
    expect(message.envelope.id).toMatch(/^evt_/);
    expect(message.envelope.data).toEqual({
      activityId: "act_1",
      status: "processed",
      at: "2026-09-24T10:00:00Z",
    });
  });

  it("generates a distinct id per call", async () => {
    const redis = createFakePublisherRedis();
    const { publishRealtimeEvent } = createRealtimePublisher(redis);

    await publishRealtimeEvent(["user:1"], ACTIVITY_PROCESSED, {
      activityId: "act_1",
      status: "processed",
      at: "2026-09-24T10:00:00Z",
    });
    await publishRealtimeEvent(["user:1"], ACTIVITY_PROCESSED, {
      activityId: "act_1",
      status: "processed",
      at: "2026-09-24T10:00:00Z",
    });

    const ids = redis.publish.mock.calls.map((call) => {
      const [, raw] = call as [string, string];
      return (JSON.parse(raw) as { envelope: { id: string } }).envelope.id;
    });
    expect(ids[0]).not.toBe(ids[1]);
  });
});

describe("createRedisEventSource", () => {
  it("delivers well-formed messages received on the realtime channel", async () => {
    const redis = createFakeSubscriberRedis();
    const source = createRedisEventSource(redis);

    await source.subscribe();
    expect(redis.subscribe).toHaveBeenCalledWith(REALTIME_CHANNEL);

    const received: unknown[] = [];
    source.onMessage((message) => received.push(message));

    const envelope = {
      v: PROTOCOL_VERSION,
      t: ACTIVITY_PROCESSED,
      id: "evt_1",
      data: { activityId: "act_1", status: "processed", at: "2026-09-24T10:00:00Z" },
    };
    redis.emitter.emit(
      "message",
      REALTIME_CHANNEL,
      JSON.stringify({ topics: ["user:1"], envelope }),
    );

    expect(received).toEqual([{ topics: ["user:1"], envelope }]);
  });

  it("ignores messages from another channel", () => {
    const redis = createFakeSubscriberRedis();
    const source = createRedisEventSource(redis);

    const received: unknown[] = [];
    source.onMessage((message) => received.push(message));

    redis.emitter.emit("message", "some:other:channel", JSON.stringify({ foo: "bar" }));

    expect(received).toEqual([]);
  });

  it("ignores unparsable or malformed payloads instead of throwing", () => {
    const redis = createFakeSubscriberRedis();
    const source = createRedisEventSource(redis);

    const received: unknown[] = [];
    source.onMessage((message) => received.push(message));

    expect(() => {
      redis.emitter.emit("message", REALTIME_CHANNEL, "not json{{{");
      redis.emitter.emit("message", REALTIME_CHANNEL, JSON.stringify({ topics: "not-an-array" }));
    }).not.toThrow();
    expect(received).toEqual([]);
  });

  it("unsubscribes, detaches its listener and closes the connection", async () => {
    const redis = createFakeSubscriberRedis();
    const source = createRedisEventSource(redis);

    const received: unknown[] = [];
    source.onMessage((message) => received.push(message));

    await source.close();

    expect(redis.unsubscribe).toHaveBeenCalledWith(REALTIME_CHANNEL);
    expect(redis.quit).toHaveBeenCalledTimes(1);

    const envelope = {
      v: PROTOCOL_VERSION,
      t: ACTIVITY_PROCESSED,
      id: "evt_1",
      data: { activityId: "act_1", status: "processed", at: "2026-09-24T10:00:00Z" },
    };
    redis.emitter.emit(
      "message",
      REALTIME_CHANNEL,
      JSON.stringify({ topics: ["user:1"], envelope }),
    );
    expect(received).toEqual([]);
  });
});
