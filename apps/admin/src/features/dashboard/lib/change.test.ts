import { describe, expect, it } from "vitest";
import { describeChange } from "./change";

/** A Growth tile's change versus the previous period of the same length (ADR-038 §15). */
describe("describeChange", () => {
  it("is a rounded percentage, signed (minus sign −), as written in French", () => {
    expect(describeChange({ value: 150, previous: 100 })).toEqual({ label: "+50 %", direction: "up" });
    expect(describeChange({ value: 2, previous: 3 })).toEqual({ label: "−33 %", direction: "down" });
  });

  it("is flat when nothing changed", () => {
    expect(describeChange({ value: 7, previous: 7 })).toEqual({ label: "0 %", direction: "flat" });
    expect(describeChange({ value: 0, previous: 0 })).toEqual({ label: "0 %", direction: "flat" });
  });

  it("has no percentage when the previous period had nothing", () => {
    expect(describeChange({ value: 4, previous: 0 })).toEqual({ label: "nouveau", direction: "up" });
  });
});
