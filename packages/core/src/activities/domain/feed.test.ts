import { describe, expect, it } from "vitest";
import { encodePolyline } from "./encode-polyline.js";
import { decodeFeedCursor, encodeFeedCursor, InvalidFeedCursorError } from "./feed-cursor.js";
import { feedPolyline } from "./feed-polyline.js";

describe("encodePolyline", () => {
  it("matches Google's reference vector", () => {
    const points = [
      { lat: 38.5, lon: -120.2 },
      { lat: 40.7, lon: -120.95 },
      { lat: 43.252, lon: -126.453 },
    ];
    expect(encodePolyline(points)).toBe("_p~iF~ps|U_ulLnnqC_mqNvxq`@");
  });

  it("returns an empty string for no points", () => {
    expect(encodePolyline([])).toBe("");
  });
});

describe("feedPolyline", () => {
  it("returns null when there is nothing to draw", () => {
    expect(feedPolyline([])).toBeNull();
    expect(feedPolyline([{ lat: 48, lon: 2 }])).toBeNull();
  });

  it("fits a long zigzag trace in the budget, keeping both ends", () => {
    const points = Array.from({ length: 20_000 }, (_, i) => ({
      lat: 45.9 + i * 0.00005,
      lon: 6.1 + (i % 2 === 0 ? 0 : 0.0004) + Math.sin(i / 50) * 0.01,
    }));
    const encoded = feedPolyline(points);
    expect(encoded).not.toBeNull();
    expect(encoded!.length).toBeLessThanOrEqual(2000);
    const first = encodePolyline([points[0]!]);
    expect(encoded!.startsWith(first)).toBe(true);
  });
});

describe("feed cursor", () => {
  it("round-trips", () => {
    const cursor = { startedAt: new Date("2026-10-02T12:32:00.123Z"), id: "7f1c2a4e-0b4d-4c55-9a51-1d0f3c3b8e21" };
    expect(decodeFeedCursor(encodeFeedCursor(cursor))).toEqual(cursor);
  });

  it("rejects garbage", () => {
    expect(() => decodeFeedCursor("not-a-cursor")).toThrow(InvalidFeedCursorError);
    expect(() => decodeFeedCursor(Buffer.from("2026-10-02T12:32:00Z|nope").toString("base64url"))).toThrow(
      InvalidFeedCursorError,
    );
  });
});
