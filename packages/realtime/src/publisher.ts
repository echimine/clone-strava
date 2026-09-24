import { randomUUID } from "node:crypto";
import type { Redis } from "ioredis";
import {
  REALTIME_CHANNEL,
  realtimeChannelMessageSchema,
  type RealtimeChannelMessage,
} from "./channel.js";
import { PROTOCOL_VERSION, type Envelope } from "./protocol.js";
import type { MobileEventDataFor, MobileEventType } from "./events.js";

// --- Publisher (ADR-010 §6, §8) ---

/** Minimal Redis surface required to publish: any connection, not necessarily dedicated. */
export type RealtimeEventPublisherRedis = Pick<Redis, "publish">;

export interface RealtimePublisher {
  /**
   * Builds the envelope (`id`, `v`) and publishes it on `REALTIME_CHANNEL`
   * for the given topics. Called only by the realtime bridge (ADR-021 §4),
   * never directly by domain modules.
   */
  publishRealtimeEvent<T extends MobileEventType>(
    topics: string[],
    type: T,
    data: MobileEventDataFor<T>,
  ): Promise<void>;
}

export function createRealtimePublisher(
  redis: RealtimeEventPublisherRedis,
): RealtimePublisher {
  return {
    async publishRealtimeEvent(topics, type, data) {
      const envelope: Envelope = {
        v: PROTOCOL_VERSION,
        t: type,
        id: `evt_${randomUUID()}`,
        // `data` is a well-formed per-event payload (see events.ts); the
        // envelope schema only cares that it is a plain record.
        data: data as Record<string, unknown>,
      };
      const message = realtimeChannelMessageSchema.parse({ topics, envelope });
      await redis.publish(REALTIME_CHANNEL, JSON.stringify(message));
    },
  };
}

// --- Event source (ADR-010 §6, §10: "the event source is behind an interface, replaceable by a fake in tests") ---

export interface RealtimeEventSource {
  /** Subscribes to the realtime channel. Must be called before events are delivered. */
  subscribe(): Promise<void>;
  /** Registers a listener invoked for every well-formed message received. */
  onMessage(listener: (message: RealtimeChannelMessage) => void): void;
  /** Unsubscribes and releases the underlying connection. */
  close(): Promise<void>;
}

/** Minimal Redis surface required to subscribe, in subscriber mode. */
export type RealtimeEventSourceRedis = Pick<
  Redis,
  "subscribe" | "unsubscribe" | "on" | "off" | "quit"
>;

/**
 * Redis-backed event source. Expects a connection dedicated to subscriber
 * mode (e.g. `redis.duplicate()`): a single ioredis instance cannot both
 * publish and subscribe (ADR-010 §2 "dedicated connection in subscriber
 * mode").
 */
export function createRedisEventSource(
  redis: RealtimeEventSourceRedis,
): RealtimeEventSource {
  const listeners = new Set<(message: RealtimeChannelMessage) => void>();

  const handleMessage = (channel: string, raw: string): void => {
    if (channel !== REALTIME_CHANNEL) {
      return;
    }

    let json: unknown;
    try {
      json = JSON.parse(raw);
    } catch {
      return;
    }

    const result = realtimeChannelMessageSchema.safeParse(json);
    if (!result.success) {
      return;
    }

    for (const listener of listeners) {
      listener(result.data);
    }
  };

  redis.on("message", handleMessage);

  return {
    async subscribe() {
      await redis.subscribe(REALTIME_CHANNEL);
    },
    onMessage(listener) {
      listeners.add(listener);
    },
    async close() {
      redis.off("message", handleMessage);
      await redis.unsubscribe(REALTIME_CHANNEL);
      await redis.quit();
    },
  };
}
