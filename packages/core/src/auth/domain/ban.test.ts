import { describe, expect, it } from "vitest";
import { activeBan, bannedUserError } from "./ban.js";

const now = new Date("2026-11-04T10:00:00Z");

describe("activeBan (ADR-038 §6)", () => {
  it("is null without a Ban", () => {
    expect(activeBan({ banned: false, banReason: null, banExpires: null }, now)).toBeNull();
  });

  it("is a permanent Ban when banned without an end", () => {
    expect(activeBan({ banned: true, banReason: "Spam", banExpires: null }, now)).toEqual({
      until: null,
      reason: "Spam",
    });
  });

  it("is a temporary Ban until its end", () => {
    const end = new Date("2026-11-05T10:00:00Z");
    expect(activeBan({ banned: true, banReason: "Spam", banExpires: end }, now)).toEqual({ until: end, reason: "Spam" });
  });

  it("is over once its end has passed, even while the row still says banned", () => {
    expect(activeBan({ banned: true, banReason: "Spam", banExpires: new Date("2026-11-04T09:59:59Z") }, now)).toBeNull();
  });
});

describe("bannedUserError: the 403 BANNED_USER body the app shows as « Compte suspendu »", () => {
  it("names the end date in Paris time, the reason and the contact address", () => {
    expect(
      bannedUserError(
        { banned: true, banReason: "Propos haineux", banExpires: new Date("2026-11-11T13:30:00Z") },
        "contact@nervo.app",
      ),
    ).toEqual({
      code: "BANNED_USER",
      message: "Votre compte est suspendu jusqu'au 11 novembre 2026 à 14:30.",
      bannedUntil: "2026-11-11T13:30:00.000Z",
      banReason: "Propos haineux",
      contactEmail: "contact@nervo.app",
    });
  });

  it("says « définitivement » for a permanent Ban, null contact when not configured", () => {
    expect(bannedUserError({ banned: true, banReason: null, banExpires: null }, null)).toEqual({
      code: "BANNED_USER",
      message: "Votre compte est suspendu définitivement.",
      bannedUntil: null,
      banReason: null,
      contactEmail: null,
    });
  });
});
