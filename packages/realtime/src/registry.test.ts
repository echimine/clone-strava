import { describe, expect, it } from "vitest";
import { TopicRegistry } from "./registry.js";

describe("TopicRegistry", () => {
  it("tracks connections per topic", () => {
    const registry = new TopicRegistry<string>();

    registry.subscribe("conn-1", "user:1");
    registry.subscribe("conn-2", "user:1");

    expect(registry.connectionsFor("user:1")).toEqual(new Set(["conn-1", "conn-2"]));
    expect(registry.size).toBe(1);
  });

  it("is idempotent on repeated subscribe", () => {
    const registry = new TopicRegistry<string>();

    registry.subscribe("conn-1", "user:1");
    registry.subscribe("conn-1", "user:1");

    expect(registry.connectionsFor("user:1")).toEqual(new Set(["conn-1"]));
    expect(registry.topicCount("conn-1")).toBe(1);
  });

  it("unsubscribes a single connection from a single topic", () => {
    const registry = new TopicRegistry<string>();

    registry.subscribe("conn-1", "user:1");
    registry.subscribe("conn-1", "user:2");
    registry.unsubscribe("conn-1", "user:1");

    expect(registry.connectionsFor("user:1").size).toBe(0);
    expect(registry.topicCount("conn-1")).toBe(1);
  });

  it("unsubscribe is a no-op for an unknown connection or topic", () => {
    const registry = new TopicRegistry<string>();

    expect(() => registry.unsubscribe("conn-1", "user:1")).not.toThrow();
    expect(registry.size).toBe(0);
  });

  it("removeConnection drops it from every topic", () => {
    const registry = new TopicRegistry<string>();

    registry.subscribe("conn-1", "user:1");
    registry.subscribe("conn-1", "user:2");
    registry.subscribe("conn-2", "user:1");

    registry.removeConnection("conn-1");

    expect(registry.connectionsFor("user:1")).toEqual(new Set(["conn-2"]));
    expect(registry.connectionsFor("user:2").size).toBe(0);
    expect(registry.topicCount("conn-1")).toBe(0);
    expect(registry.size).toBe(1);
  });

  it("cleans up empty topic entries so size reflects only active topics", () => {
    const registry = new TopicRegistry<string>();

    registry.subscribe("conn-1", "user:1");
    registry.unsubscribe("conn-1", "user:1");

    expect(registry.size).toBe(0);
  });
});
