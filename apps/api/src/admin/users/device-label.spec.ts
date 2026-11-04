import { describe, expect, it } from "vitest";
import { deviceLabel } from "./device-label.js";

describe("deviceLabel: a session's device from its user agent (ADR-038 §5)", () => {
  it.each([
    ["Nervo/42 CFNetwork/3826.400.120 Darwin/25.0.0", "App iOS"],
    [
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
      "Chrome sur macOS",
    ],
    [
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Safari/605.1.15",
      "Safari sur macOS",
    ],
    [
      "Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1",
      "Safari sur iPhone",
    ],
    ["Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:132.0) Gecko/20100101 Firefox/132.0", "Firefox sur Windows"],
    [
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0",
      "Edge sur Windows",
    ],
    [
      "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36",
      "Chrome sur Android",
    ],
  ])("%s → %s", (userAgent, label) => {
    expect(deviceLabel(userAgent)).toBe(label);
  });

  it("is null without a user agent, and the raw text for an unknown one", () => {
    expect(deviceLabel(null)).toBeNull();
    expect(deviceLabel("  ")).toBeNull();
    expect(deviceLabel("curl/8.7.1")).toBe("curl/8.7.1");
  });
});
