import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import type {
  ActivityDetail,
  AthleteProfileResponse,
  CreateReportRequest,
  CreateReportResponse,
  FeedResponse,
  GalleryResponse,
  ListCommentsResponse,
  SegmentSheet,
} from "@repo/contracts";
import { REPORT_LIMIT_PER_DAY } from "@repo/contracts";
import { bootstrapAthleteApp, type AthleteApp } from "../testing/athlete-app.js";
import { segmentSeeds } from "../testing/segment-seeds.js";

/**
 * `POST /v1/reports` (ADR-038 §9, §10) over the real `AppModule`: cases and Reports, the copy of
 * the target's texts, the rules, and the reported item hidden for the reporter on every read path
 * through the viewer filter (§7).
 */
describe("reports (integration)", () => {
  let api: AthleteApp;
  let reporter: string;
  let author: string;

  const report = (as: string, body: CreateReportRequest) => api.call("/reports", as, { method: "POST", body });

  async function errorCode(response: Response) {
    return ((await response.json()) as { error: { code: string } }).error.code;
  }

  async function get<T>(path: string, as = reporter): Promise<T> {
    const response = await api.call(path, as);
    expect(response.status, path).toBe(200);
    return (await response.json()) as T;
  }

  const comment = async (userId: string, activityId: string, body: string) =>
    (
      await api.sql<{ id: string }>(
        "insert into engagement.comment (user_id, activity_id, body) values ($1, $2, $3) returning id",
        [userId, activityId, body],
      )
    )[0]!.id;

  const casesOf = (targetId: string) =>
    api.sql<{ id: string; target_type: string; target_user_id: string; status: string }>(
      "select id, target_type, target_user_id, status from moderation.report_case where target_id = $1",
      [targetId],
    );

  const reportsOf = (caseId: string) =>
    api.sql<{ reporter_id: string; reason: string; note: string | null; snapshot: unknown }>(
      "select reporter_id, reason, note, snapshot from moderation.report where case_id = $1 order by created_at",
      [caseId],
    );

  beforeAll(async () => {
    api = await bootstrapAthleteApp();
  }, 60_000);

  afterAll(async () => {
    await api?.close();
  });

  beforeEach(async () => {
    reporter = await api.seedAthlete("Rita");
    author = await api.seedAthlete("Auteur", { bio: "Ma bio", avatarKey: "avatars/x/y.jpg" });
    await api.sql("insert into social.follow (follower_id, followee_id, status) values ($1, $2, 'accepted')", [
      reporter,
      author,
    ]);
  });

  it("reports a comment: 201, a case opens with a copy of the text, and the comment disappears for the reporter only", async () => {
    const activity = await api.seedActivity(author);
    const target = await comment(author, activity, "Texte injurieux");
    await comment(author, activity, "Autre commentaire");

    const response = await report(reporter, { targetType: "comment", targetId: target, reason: "harassment" });
    expect(response.status).toBe(201);
    const { id } = (await response.json()) as CreateReportResponse;

    const [reportCase] = await casesOf(target);
    expect(reportCase).toMatchObject({ target_type: "comment", target_user_id: author, status: "open" });
    expect(await reportsOf(reportCase!.id)).toEqual([
      { reporter_id: reporter, reason: "harassment", note: null, snapshot: { body: "Texte injurieux", activityId: activity } },
    ]);
    expect(id).toEqual(expect.any(String));

    const mine = await get<ListCommentsResponse>(`/activities/${activity}/comments`);
    expect(mine.items.map((item) => item.body)).toEqual(["Autre commentaire"]);
    expect((await api.call(`/activities/${activity}/comments/${target}`, reporter)).status).toBe(404);
    expect((await get<ActivityDetail>(`/activities/${activity}`)).engagement.commentCount).toBe(2);
    const theirs = await get<ListCommentsResponse>(`/activities/${activity}/comments`, author);
    expect(theirs.items).toHaveLength(2);
  });

  it("answers 200 with the same Report on a repeat while the case is open, and writes nothing", async () => {
    const activity = await api.seedActivity(author);
    const target = await comment(author, activity, "Spam");
    const first = (await (await report(reporter, { targetType: "comment", targetId: target, reason: "spam" })).json()) as CreateReportResponse;

    const repeat = await report(reporter, { targetType: "comment", targetId: target, reason: "other", note: "Encore" });
    expect(repeat.status).toBe(200);
    expect(((await repeat.json()) as CreateReportResponse).id).toBe(first.id);
    const [reportCase] = await casesOf(target);
    expect(await reportsOf(reportCase!.id)).toHaveLength(1);
  });

  it("joins a second reporter to the open case, and opens a new case once the first is closed", async () => {
    const activity = await api.seedActivity(author);
    const other = await api.seedAthlete("Oscar");

    expect((await report(reporter, { targetType: "activity", targetId: activity, reason: "spam" })).status).toBe(201);
    expect((await report(other, { targetType: "activity", targetId: activity, reason: "other", note: " Pub " })).status).toBe(201);
    const [reportCase] = await casesOf(activity);
    expect((await reportsOf(reportCase!.id)).map((row) => [row.reason, row.note])).toEqual([
      ["spam", null],
      ["other", "Pub"],
    ]);

    await api.sql("update moderation.report_case set status = 'dismissed', closed_at = now() where id = $1", [reportCase!.id]);
    expect((await report(other, { targetType: "activity", targetId: activity, reason: "spam" })).status).toBe(201);
    expect((await casesOf(activity)).map((row) => row.status).sort()).toEqual(["dismissed", "open"]);
  });

  it("reports an Activity as a whole: copies title, description and Media ids; it leaves the feed, the profile and the Gallery, and its detail is 404", async () => {
    const activity = await api.seedActivity(author, { title: "Titre choquant", description: "Description" });
    const kept = await api.seedActivity(author);
    const mediaId = crypto.randomUUID();
    await api.sql(
      `insert into activities.activity_media (id, activity_id, s3_key, kind, width, height, position)
       values ($1, $2, $3, 'photo', 100, 100, 0)`,
      [mediaId, activity, `activities/${author}/${activity}/media/${mediaId}/`],
    );

    expect((await report(reporter, { targetType: "activity", targetId: activity, reason: "sexual_or_violent" })).status).toBe(201);

    const [reportCase] = await casesOf(activity);
    expect((await reportsOf(reportCase!.id))[0]!.snapshot).toEqual({
      title: "Titre choquant",
      description: "Description",
      mediaIds: [mediaId],
    });
    expect((await get<FeedResponse>("/feed?limit=50")).items.map((item) => item.id)).toEqual([kept]);
    expect((await get<FeedResponse>(`/athletes/${author}/activities`)).items.map((item) => item.id)).toEqual([kept]);
    expect((await get<GalleryResponse>(`/athletes/${author}/media`)).items).toEqual([]);
    const detail = await api.call(`/activities/${activity}`, reporter);
    expect(detail.status).toBe(404);
    expect(await errorCode(detail)).toBe("activity_not_found");
    expect((await api.call(`/activities/${activity}`, author)).status).toBe(200);
  });

  it("reports an athlete: copies name, bio and Avatar key, and never hides them", async () => {
    const response = await report(reporter, { targetType: "athlete", targetId: author, reason: "impersonation" });
    expect(response.status).toBe(201);

    const [reportCase] = await casesOf(author);
    expect((await reportsOf(reportCase!.id))[0]!.snapshot).toEqual({
      name: "Auteur Testeur",
      bio: "Ma bio",
      avatarKey: "avatars/x/y.jpg",
    });
    expect((await get<AthleteProfileResponse>(`/athletes/${author}`)).athlete.id).toBe(author);
  });

  it("reports a Segment: copies its name, the case points at its creator (none for a Segment without one), and it stays visible", async () => {
    const seeds = segmentSeeds(api);
    const created = await seeds.segment({ name: "Montée injurieuse", createdBy: author });
    const orphan = await seeds.segment({ name: "Col sans créateur", createdBy: null });

    for (const segment of [created, orphan]) {
      const response = await report(reporter, { targetType: "segment", targetId: segment, reason: "spam" });
      expect(response.status).toBe(201);
    }

    const [createdCase] = await casesOf(created);
    expect(createdCase).toMatchObject({ target_type: "segment", target_user_id: author, status: "open" });
    expect((await reportsOf(createdCase!.id))[0]!.snapshot).toEqual({ name: "Montée injurieuse" });
    const [orphanCase] = await casesOf(orphan);
    expect(orphanCase).toMatchObject({ target_type: "segment", target_user_id: null });
    expect((await get<SegmentSheet>(`/segments/${created}`)).name).toBe("Montée injurieuse");

    const own = await report(author, { targetType: "segment", targetId: created, reason: "spam" });
    expect(own.status).toBe(422);
    expect(await errorCode(own)).toBe("cannot_report_own_content");
    const missing = await report(reporter, { targetType: "segment", targetId: crypto.randomUUID(), reason: "spam" });
    expect(missing.status).toBe(404);
    expect(await errorCode(missing)).toBe("segment_not_found");
    await seeds.cleanup();
  });

  it("answers 404 for a missing or invisible target", async () => {
    const privateActivity = await api.seedActivity(author, { visibility: "private" });
    for (const [targetType, targetId, code] of [
      ["activity", privateActivity, "activity_not_found"],
      ["comment", crypto.randomUUID(), "comment_not_found"],
      ["athlete", crypto.randomUUID(), "athlete_not_found"],
    ] as const) {
      const response = await report(reporter, { targetType, targetId, reason: "spam" });
      expect(response.status, targetType).toBe(404);
      expect(await errorCode(response)).toBe(code);
    }
    expect(await casesOf(privateActivity)).toEqual([]);
  });

  it("answers 422 for one's own content, a missing note with « other », or impersonation of a non-athlete", async () => {
    const own = await api.seedActivity(reporter);
    const theirs = await api.seedActivity(author);
    const cases: [CreateReportRequest, string][] = [
      [{ targetType: "activity", targetId: own, reason: "spam" }, "cannot_report_own_content"],
      [{ targetType: "athlete", targetId: reporter, reason: "spam" }, "cannot_report_own_content"],
      [{ targetType: "activity", targetId: theirs, reason: "other", note: "  " }, "note_required"],
      [{ targetType: "activity", targetId: theirs, reason: "impersonation" }, "reason_not_allowed"],
    ];
    for (const [body, code] of cases) {
      const response = await report(reporter, body);
      expect(response.status, code).toBe(422);
      expect(await errorCode(response)).toBe(code);
    }
    expect(await casesOf(theirs)).toEqual([]);
  });

  it(`answers 429 past ${REPORT_LIMIT_PER_DAY} Reports per 24 h, with Retry-After`, async () => {
    const targets = await Promise.all(
      Array.from({ length: REPORT_LIMIT_PER_DAY + 1 }, () => api.seedAthlete("Cible")),
    );
    for (const target of targets.slice(0, REPORT_LIMIT_PER_DAY)) {
      expect((await report(reporter, { targetType: "athlete", targetId: target, reason: "spam" })).status).toBe(201);
    }
    const over = await report(reporter, { targetType: "athlete", targetId: targets.at(-1)!, reason: "spam" });
    expect(over.status).toBe(429);
    expect(await errorCode(over)).toBe("report_limit_reached");
    expect(Number(over.headers.get("retry-after"))).toBeGreaterThan(86_000);

    // Reports older than 24 h no longer count.
    await api.sql("update moderation.report set created_at = now() - interval '25 hours' where reporter_id = $1", [
      reporter,
    ]);
    expect((await report(reporter, { targetType: "athlete", targetId: targets.at(-1)!, reason: "spam" })).status).toBe(201);
  });
});
