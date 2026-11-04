import { describe, expect, it } from "vitest";
import { checkReport } from "./report.js";

describe("checkReport (ADR-038 §9)", () => {
  it("requires a note with « Autre », blank counting as none", () => {
    expect(checkReport("comment", "other", undefined)).toEqual({ violation: "note_required" });
    expect(checkReport("comment", "other", "   ")).toEqual({ violation: "note_required" });
    expect(checkReport("comment", "other", "  Propos déplacés ")).toEqual({ note: "Propos déplacés" });
  });

  it("keeps « Usurpation d'identité » for an athlete", () => {
    expect(checkReport("athlete", "impersonation", undefined)).toEqual({ note: null });
    expect(checkReport("activity", "impersonation", undefined)).toEqual({ violation: "reason_not_allowed" });
    expect(checkReport("comment", "impersonation", "x")).toEqual({ violation: "reason_not_allowed" });
  });

  it("leaves the note optional for the other reasons", () => {
    expect(checkReport("activity", "spam", "")).toEqual({ note: null });
    expect(checkReport("activity", "harassment", "Insultes")).toEqual({ note: "Insultes" });
  });
});
