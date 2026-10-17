import { describe, expect, it } from "vitest";
import {
  PROTOCOL_VERSION,
  clientMessageSchema,
  envelopeSchema,
  parseClientMessage,
} from "./protocol.js";

describe("envelopeSchema", () => {
  it("encodes and decodes a valid envelope", () => {
    const envelope = {
      v: PROTOCOL_VERSION,
      t: "activity.processed",
      id: "evt_123",
      data: { activityId: "act_1", status: "processed", at: "2026-09-24T10:00:00Z" },
    };

    const encoded = JSON.stringify(envelope);
    const decoded = envelopeSchema.parse(JSON.parse(encoded));

    expect(decoded).toEqual(envelope);
  });

  it("rejects an envelope with an unknown protocol version", () => {
    const result = envelopeSchema.safeParse({
      v: 999,
      t: "activity.processed",
      id: "evt_123",
      data: {},
    });

    expect(result.success).toBe(false);
  });
});

describe("parseClientMessage", () => {
  it("parses a valid sub message", () => {
    const result = parseClientMessage(JSON.stringify({ a: "sub", topic: "user:123" }));

    expect(result).toEqual({
      success: true,
      message: { a: "sub", topic: "user:123" },
    });
  });

  it("parses a sub message carrying a subscription grant (ADR-034 §5)", () => {
    const result = parseClientMessage(JSON.stringify({ a: "sub", topic: "activity:42", grant: "g.r.ant" }));

    expect(result).toEqual({
      success: true,
      message: { a: "sub", topic: "activity:42", grant: "g.r.ant" },
    });
  });

  it("parses a valid ping message", () => {
    const result = parseClientMessage(JSON.stringify({ a: "ping" }));

    expect(result).toEqual({ success: true, message: { a: "ping" } });
  });

  it("never throws on unreadable JSON (ADR-010 §5)", () => {
    expect(() => parseClientMessage("not json{{{")).not.toThrow();
    expect(parseClientMessage("not json{{{")).toEqual({ success: false });
  });

  it("rejects a well-formed JSON payload with an unknown action", () => {
    const result = parseClientMessage(JSON.stringify({ a: "explode" }));

    expect(result).toEqual({ success: false });
  });

  it("rejects a message missing required fields", () => {
    const result = parseClientMessage(JSON.stringify({ a: "sub" }));

    expect(result).toEqual({ success: false });
  });

  it("rejects non-object JSON", () => {
    expect(parseClientMessage("42")).toEqual({ success: false });
    expect(parseClientMessage("null")).toEqual({ success: false });
    expect(parseClientMessage('"hello"')).toEqual({ success: false });
  });

  it("keeps clientMessageSchema and parseClientMessage in sync", () => {
    const raw = JSON.stringify({ a: "unsub", topic: "user:42" });
    const parsed = parseClientMessage(raw);

    expect(parsed.success).toBe(true);
    if (parsed.success) {
      expect(() => clientMessageSchema.parse(parsed.message)).not.toThrow();
    }
  });
});
