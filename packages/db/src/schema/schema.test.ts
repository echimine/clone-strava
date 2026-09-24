import { getTableConfig } from "drizzle-orm/pg-core";
import { describe, expect, it } from "vitest";
import { activity, activityAttachment, activityStats, activityTrack } from "./activities.js";
import { user } from "./auth.js";
import { comment, kudos } from "./engagement.js";
import { segment, segmentEffort } from "./segments.js";
import { follow } from "./social.js";
import { sportType } from "./sports.js";
import { userSubscription } from "./subscriptions.js";
import { userProfile } from "./users.js";

describe("schema table names and owning PostgreSQL schema (ADR-017, ADR-021 §7)", () => {
  it("keeps Better Auth's `user` table in the public schema", () => {
    const config = getTableConfig(user);
    expect(config.name).toBe("user");
    expect(config.schema).toBeUndefined();
  });

  it("puts each domain module's tables in a schema named after it", () => {
    expect(getTableConfig(userProfile)).toMatchObject({ name: "user_profile", schema: "users" });
    expect(getTableConfig(sportType)).toMatchObject({ name: "sport_type", schema: "sports" });
    expect(getTableConfig(follow)).toMatchObject({ name: "follow", schema: "social" });
    expect(getTableConfig(activity)).toMatchObject({ name: "activity", schema: "activities" });
    expect(getTableConfig(activityStats)).toMatchObject({
      name: "activity_stats",
      schema: "activities",
    });
    expect(getTableConfig(activityTrack)).toMatchObject({
      name: "activity_track",
      schema: "activities",
    });
    expect(getTableConfig(activityAttachment)).toMatchObject({
      name: "activity_attachment",
      schema: "activities",
    });
    expect(getTableConfig(kudos)).toMatchObject({ name: "kudos", schema: "engagement" });
    expect(getTableConfig(comment)).toMatchObject({ name: "comment", schema: "engagement" });
    expect(getTableConfig(segment)).toMatchObject({ name: "segment", schema: "segments" });
    expect(getTableConfig(segmentEffort)).toMatchObject({
      name: "segment_effort",
      schema: "segments",
    });
    expect(getTableConfig(userSubscription)).toMatchObject({
      name: "user_subscription",
      schema: "subscriptions",
    });
  });

  it("gives `activity` no default id, unlike server-generated identifiers", () => {
    const config = getTableConfig(activity);
    const idColumn = config.columns.find((column) => column.name === "id");
    expect(idColumn?.hasDefault).toBe(false);

    const statsIdColumn = getTableConfig(userProfile).columns.find((c) => c.name === "user_id");
    expect(statsIdColumn?.primary).toBe(true);
  });

  it("declares the GiST indexes required for spatial queries", () => {
    const trackIndexes = getTableConfig(activityTrack).indexes;
    expect(trackIndexes.some((i) => i.config.method === "gist")).toBe(true);

    const segmentIndexes = getTableConfig(segment).indexes;
    expect(segmentIndexes.some((i) => i.config.method === "gist")).toBe(true);
  });
});
