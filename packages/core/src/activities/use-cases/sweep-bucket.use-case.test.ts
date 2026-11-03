import { describe, expect, it, vi } from "vitest";
import { activityMediaKey } from "@repo/contracts";
import { SweepBucketUseCase } from "./sweep-bucket.use-case.js";

const USER = "11111111-1111-4111-8111-111111111111";
const ACTIVITY = "22222222-2222-4222-8222-222222222222";
const MEDIA = "33333333-3333-4333-8333-333333333333";
const NOW = new Date(Date.UTC(2026, 10, 3));
const EIGHT_DAYS_AGO = new Date(NOW.getTime() - 8 * 24 * 3_600_000);

/**
 * The sweep against a confirmation committed while it runs (ADR-037 §11): the bucket in memory,
 * the database reads faked so the `activity_media` row appears right after the sweep's first read.
 */
function setup() {
  const keys = ["original.jpg", "thumb.jpg"].map((file) => activityMediaKey(USER, ACTIVITY, MEDIA, file));
  const storage = {
    listKeys: vi.fn(async (prefix: string) =>
      keys.filter((key) => key.startsWith(prefix)).map((key) => ({ key, lastModified: EIGHT_DAYS_AGO })),
    ),
    deleteObjects: vi.fn(async (_keys: readonly string[]) => undefined),
  };
  let confirmed = false;
  const references = {
    activityOwners: vi.fn(async (ids: readonly string[]) =>
      ids.includes(ACTIVITY) ? [{ id: ACTIVITY, userId: USER }] : [],
    ),
    mediaActivities: vi.fn(async () => {
      // The confirmation commits just after this read.
      const rows = confirmed ? [{ id: MEDIA, activityId: ACTIVITY }] : [];
      confirmed = true;
      return rows;
    }),
    importOwners: vi.fn(async () => []),
  };
  const useCase = new SweepBucketUseCase(references as never, storage as never);
  return { useCase, storage };
}

describe("SweepBucketUseCase", () => {
  it("keeps a Media folder confirmed between its first read and the delete", async () => {
    const { useCase, storage } = setup();

    const deleted = await useCase.execute(NOW);

    expect(deleted).toBe(0);
    const sent = storage.deleteObjects.mock.calls.flatMap(([keys]) => keys);
    expect(sent).toEqual([]);
  });
});
