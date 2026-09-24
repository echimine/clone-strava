import { describe, expect, it } from "vitest";
import { userTopic } from "@repo/realtime";
import { createConnectionState } from "./connection-state.js";
import {
  handleClientMessage,
  handleSubMessage,
  handleUnsubMessage,
  recordMessageAndCheckQuota,
} from "./message-handling.js";
import { MAX_MESSAGES_PER_WINDOW, MAX_TOPICS_PER_CONNECTION, MESSAGE_WINDOW_MS } from "./quotas.js";

const USER_ID = "22222222-2222-4222-8222-222222222222";
const ALLOWED_TOPIC = userTopic(USER_ID);

describe("handleSubMessage", () => {
  it("subscribes to a topic present in the token", () => {
    const state = createConnectionState({ sub: USER_ID, topics: [ALLOWED_TOPIC] }, 0);
    expect(handleSubMessage(state, ALLOWED_TOPIC)).toBe("ok");
    expect(state.topics.has(ALLOWED_TOPIC)).toBe(true);
  });

  it("rejects a topic absent from the token (forbidden)", () => {
    const state = createConnectionState({ sub: USER_ID, topics: [ALLOWED_TOPIC] }, 0);
    expect(handleSubMessage(state, "user:someone-else")).toBe("forbidden");
    expect(state.topics.size).toBe(0);
  });

  it("is idempotent when re-subscribing to the same topic", () => {
    const state = createConnectionState({ sub: USER_ID, topics: [ALLOWED_TOPIC] }, 0);
    handleSubMessage(state, ALLOWED_TOPIC);
    expect(handleSubMessage(state, ALLOWED_TOPIC)).toBe("ok");
    expect(state.topics.size).toBe(1);
  });

  it("rejects a new topic once the per-connection quota is reached (limit)", () => {
    const topics = Array.from({ length: MAX_TOPICS_PER_CONNECTION + 1 }, (_, i) => `user:${i}`);
    const state = createConnectionState({ sub: USER_ID, topics }, 0);
    for (const topic of topics.slice(0, MAX_TOPICS_PER_CONNECTION)) {
      expect(handleSubMessage(state, topic)).toBe("ok");
    }
    expect(handleSubMessage(state, topics[MAX_TOPICS_PER_CONNECTION]!)).toBe("limit");
  });
});

describe("handleUnsubMessage", () => {
  it("removes a subscribed topic", () => {
    const state = createConnectionState({ sub: USER_ID, topics: [ALLOWED_TOPIC] }, 0);
    handleSubMessage(state, ALLOWED_TOPIC);
    handleUnsubMessage(state, ALLOWED_TOPIC);
    expect(state.topics.has(ALLOWED_TOPIC)).toBe(false);
  });

  it("is a no-op when not subscribed", () => {
    const state = createConnectionState({ sub: USER_ID, topics: [ALLOWED_TOPIC] }, 0);
    expect(() => handleUnsubMessage(state, ALLOWED_TOPIC)).not.toThrow();
  });
});

describe("recordMessageAndCheckQuota", () => {
  it("stays within quota under the limit", () => {
    const state = createConnectionState({ sub: USER_ID, topics: [] }, 0);
    for (let i = 0; i < MAX_MESSAGES_PER_WINDOW; i++) {
      expect(recordMessageAndCheckQuota(state, i)).toBe(true);
    }
  });

  it("exceeds quota past the limit within the same window", () => {
    const state = createConnectionState({ sub: USER_ID, topics: [] }, 0);
    let last = true;
    for (let i = 0; i < MAX_MESSAGES_PER_WINDOW + 1; i++) {
      last = recordMessageAndCheckQuota(state, i);
    }
    expect(last).toBe(false);
  });

  it("resets once messages fall outside the sliding window", () => {
    const state = createConnectionState({ sub: USER_ID, topics: [] }, 0);
    for (let i = 0; i < MAX_MESSAGES_PER_WINDOW + 1; i++) {
      recordMessageAndCheckQuota(state, i);
    }
    expect(recordMessageAndCheckQuota(state, MESSAGE_WINDOW_MS + 1_000)).toBe(true);
  });
});

describe("handleClientMessage", () => {
  it("dispatches a sub message", () => {
    const state = createConnectionState({ sub: USER_ID, topics: [ALLOWED_TOPIC] }, 0);
    const result = handleClientMessage(state, { a: "sub", topic: ALLOWED_TOPIC });
    expect(result).toEqual({ kind: "sub", topic: ALLOWED_TOPIC, result: "ok" });
  });

  it("dispatches a ping message", () => {
    const state = createConnectionState({ sub: USER_ID, topics: [] }, 0);
    expect(handleClientMessage(state, { a: "ping" })).toEqual({ kind: "ping" });
  });
});
