import { UnprocessableEntityException } from "@nestjs/common";
import { describe, expect, it, vi } from "vitest";
import { decodeFeedCursor, encodeFeedCursor } from "../domain/feed-cursor.js";
import { GetFeedPageUseCase } from "./get-feed-page.use-case.js";

const VIEWER = "11111111-1111-4111-8111-111111111111";
const FRIEND = "22222222-2222-4222-8222-222222222222";

function activity(index: number, userId = VIEWER) {
  return {
    id: `00000000-0000-4000-8000-00000000000${index}`,
    userId,
    sportTypeCode: "run",
    title: `Run ${index}`,
    visibility: "public" as const,
    processingStatus: "processed" as const,
    startedAt: new Date(Date.UTC(2026, 9, 2, 12 - index)),
  };
}

function setup(rows: ReturnType<typeof activity>[], followeeIds: string[] = []) {
  const social = { getFolloweeIds: vi.fn().mockResolvedValue(followeeIds) };
  const activities = { findFeedPage: vi.fn().mockResolvedValue(rows) };
  const stats = {
    findByActivityIds: vi.fn(async (ids: string[]) =>
      ids.map((activityId) => ({ activityId, distanceM: 10_000, movingTimeS: 3000, elapsedTimeS: 3100, elevationGainM: 120 })),
    ),
  };
  const tracks = {
    findFeedFieldsByActivityIds: vi.fn(async (ids: string[]) =>
      ids.map((activityId) => ({ activityId, mapPolyline: "_p~iF~ps|U", locationName: "Annecy, Haute-Savoie" })),
    ),
  };
  const useCase = new GetFeedPageUseCase(social as never, activities as never, stats as never, tracks as never);
  return { useCase, social, activities, stats, tracks };
}

describe("GetFeedPageUseCase", () => {
  it("includes the viewer even without followees and merges stats and map fields", async () => {
    const { useCase, activities } = setup([activity(1)]);
    const page = await useCase.execute(VIEWER, { limit: 20 });

    expect(activities.findFeedPage).toHaveBeenCalledWith({ viewerId: VIEWER, followeeIds: [], before: undefined, limit: 20 });
    expect(page.nextCursor).toBeNull();
    expect(page.items[0]).toMatchObject({
      title: "Run 1",
      stats: { distanceM: 10_000, elevationGainM: 120 },
      mapPolyline: "_p~iF~ps|U",
      locationName: "Annecy, Haute-Savoie",
    });
  });

  it("returns a cursor on the last kept row when one more row exists", async () => {
    const rows = [activity(1), activity(2, FRIEND), activity(3)];
    const { useCase } = setup(rows, [FRIEND]);
    const page = await useCase.execute(VIEWER, { limit: 2 });

    expect(page.items.map((item) => item.id)).toEqual([rows[0]!.id, rows[1]!.id]);
    expect(decodeFeedCursor(page.nextCursor!)).toEqual({ startedAt: rows[1]!.startedAt, id: rows[1]!.id });
  });

  it("passes a decoded cursor through and rejects invalid ones with 422", async () => {
    const { useCase, activities } = setup([]);
    const before = { startedAt: new Date("2026-10-01T08:00:00Z"), id: activity(4).id };
    await useCase.execute(VIEWER, { cursor: encodeFeedCursor(before), limit: 20 });
    expect(activities.findFeedPage).toHaveBeenCalledWith(expect.objectContaining({ before }));

    await expect(useCase.execute(VIEWER, { cursor: "garbage", limit: 20 })).rejects.toBeInstanceOf(
      UnprocessableEntityException,
    );
  });
});
