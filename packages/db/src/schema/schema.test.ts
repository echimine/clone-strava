import { getTableConfig } from "drizzle-orm/pg-core";
import { describe, expect, it } from "vitest";
import {
  activity,
  activityAnalysis,
  activityMedia,
  activityStats,
  activityTrack,
} from "./activities.js";
import { adminAuditEntry } from "./audit.js";
import { user } from "./auth.js";
import { comment, kudos } from "./engagement.js";
import { itinerary, itineraryLeg, itineraryWaypoint } from "./itineraries.js";
import { report, reportCase } from "./moderation.js";
import { segment, segmentEffort } from "./segments.js";
import { athleteBlock, follow, followSettings } from "./social.js";
import { sportType } from "./sports.js";
import { userSubscription } from "./subscriptions.js";
import { userProfile, userSport } from "./users.js";

describe("schema table names and owning PostgreSQL schema (ADR-017, ADR-021 §7)", () => {
  it("keeps Better Auth's `user` table in the public schema", () => {
    const config = getTableConfig(user);
    expect(config.name).toBe("user");
    expect(config.schema).toBeUndefined();
  });

  it("puts each domain module's tables in a schema named after it", () => {
    expect(getTableConfig(userProfile)).toMatchObject({ name: "user_profile", schema: "users" });
    expect(getTableConfig(userSport)).toMatchObject({ name: "user_sport", schema: "users" });
    expect(getTableConfig(sportType)).toMatchObject({ name: "sport_type", schema: "sports" });
    expect(getTableConfig(follow)).toMatchObject({ name: "follow", schema: "social" });
    expect(getTableConfig(followSettings)).toMatchObject({
      name: "follow_settings",
      schema: "social",
    });
    expect(getTableConfig(activity)).toMatchObject({ name: "activity", schema: "activities" });
    expect(getTableConfig(activityStats)).toMatchObject({
      name: "activity_stats",
      schema: "activities",
    });
    expect(getTableConfig(activityTrack)).toMatchObject({
      name: "activity_track",
      schema: "activities",
    });
    expect(getTableConfig(activityAnalysis)).toMatchObject({
      name: "activity_analysis",
      schema: "activities",
    });
    expect(getTableConfig(activityMedia)).toMatchObject({
      name: "activity_media",
      schema: "activities",
    });
    expect(getTableConfig(kudos)).toMatchObject({ name: "kudos", schema: "engagement" });
    expect(getTableConfig(comment)).toMatchObject({ name: "comment", schema: "engagement" });
    expect(getTableConfig(segment)).toMatchObject({ name: "segment", schema: "segments" });
    expect(getTableConfig(segmentEffort)).toMatchObject({
      name: "segment_effort",
      schema: "segments",
    });
    expect(getTableConfig(itinerary)).toMatchObject({ name: "itinerary", schema: "itineraries" });
    expect(getTableConfig(itineraryWaypoint)).toMatchObject({
      name: "itinerary_waypoint",
      schema: "itineraries",
    });
    expect(getTableConfig(itineraryLeg)).toMatchObject({ name: "itinerary_leg", schema: "itineraries" });
    expect(getTableConfig(userSubscription)).toMatchObject({
      name: "user_subscription",
      schema: "subscriptions",
    });
    expect(getTableConfig(adminAuditEntry)).toMatchObject({ name: "admin_audit_entry", schema: "audit" });
    expect(getTableConfig(athleteBlock)).toMatchObject({ name: "athlete_block", schema: "social" });
    expect(getTableConfig(reportCase)).toMatchObject({ name: "report_case", schema: "moderation" });
    expect(getTableConfig(report)).toMatchObject({ name: "report", schema: "moderation" });
  });

  it("keeps a case's target and author as plain ids, so the case outlives them (ADR-038 §10, §18)", () => {
    expect(getTableConfig(reportCase).foreignKeys).toHaveLength(0);
  });

  it("keeps the Journal free of foreign keys, so an entry outlives the accounts it names (ADR-038 §3)", () => {
    expect(getTableConfig(adminAuditEntry).foreignKeys).toHaveLength(0);
  });

  it("gives `activity` and `itinerary` no default id, unlike server-generated identifiers", () => {
    const config = getTableConfig(activity);
    const idColumn = config.columns.find((column) => column.name === "id");
    expect(idColumn?.hasDefault).toBe(false);

    const itineraryId = getTableConfig(itinerary).columns.find((column) => column.name === "id");
    expect(itineraryId?.hasDefault).toBe(false);

    const statsIdColumn = getTableConfig(userProfile).columns.find((c) => c.name === "user_id");
    expect(statsIdColumn?.primary).toBe(true);
  });

  it("declares the GiST indexes required for spatial queries", () => {
    const trackIndexes = getTableConfig(activityTrack).indexes;
    expect(trackIndexes.some((i) => i.config.method === "gist")).toBe(true);

    const segmentIndexes = getTableConfig(segment).indexes;
    expect(segmentIndexes.some((i) => i.config.method === "gist")).toBe(true);
  });

  it("gives the Itinerary track no GiST index, never searched spatially (ADR-030 §5)", () => {
    expect(getTableConfig(itinerary).indexes.some((i) => i.config.method === "gist")).toBe(false);
  });
});

describe("ADR-036 schema", () => {
  it("indexes follows by follower and status, for the following list and counts (§1)", () => {
    const followerIndex = getTableConfig(follow).indexes.find(
      (i) => i.config.name === "follow_follower_status_idx",
    );
    expect(followerIndex?.config.columns.map((c) => ("name" in c ? c.name : undefined))).toEqual([
      "follower_id",
      "status",
    ]);
  });

  it("does not approve followers unless the athlete asked to (§1)", () => {
    const approve = getTableConfig(followSettings).columns.find((c) => c.name === "approve_followers");
    expect(approve).toMatchObject({ notNull: true, default: false });
  });

  it("marks a route as untrimmed by default (§5)", () => {
    const trimmed = getTableConfig(activityTrack).columns.find((c) => c.name === "route_trimmed");
    expect(trimmed).toMatchObject({ notNull: true, default: false });
  });

  it("requires a version and splits on an Activity analysis, series being optional (§6)", () => {
    const columns = getTableConfig(activityAnalysis).columns;
    const byName = (name: string) => columns.find((c) => c.name === name);
    expect(byName("activity_id")?.primary).toBe(true);
    expect(byName("version")).toMatchObject({ notNull: true, columnType: "PgSmallInt" });
    expect(byName("splits")).toMatchObject({ notNull: true, columnType: "PgJsonb" });
    expect(byName("series")).toMatchObject({ notNull: false, columnType: "PgJsonb" });
    expect(byName("computed_at")).toMatchObject({ notNull: true, hasDefault: true });
  });
});

describe("ADR-037 schema", () => {
  it("stores a Media with its dimensions, a duration only for videos, and its folder key (§12)", () => {
    const columns = getTableConfig(activityMedia).columns;
    const byName = (name: string) => columns.find((c) => c.name === name);
    expect(byName("kind")).toMatchObject({ notNull: true, enumValues: ["photo", "video"] });
    expect(byName("width")).toMatchObject({ notNull: true, columnType: "PgInteger" });
    expect(byName("height")).toMatchObject({ notNull: true, columnType: "PgInteger" });
    expect(byName("duration_ms")).toMatchObject({ notNull: false, columnType: "PgInteger" });
    expect(byName("s3_key")).toMatchObject({ notNull: true });
  });

  it("puts the map before the Media unless the athlete chose otherwise (§8, §12)", () => {
    const mediaFirst = getTableConfig(activity).columns.find((c) => c.name === "media_first");
    expect(mediaFirst).toMatchObject({ notNull: true, default: false });
  });

  it("keeps the Avatar as an optional object key, not a URL (§2, §12)", () => {
    const columns = getTableConfig(userProfile).columns.map((c) => c.name);
    expect(columns).toContain("avatar_key");
    expect(columns).not.toContain("avatar_url");
  });
});
