import { describe, expect, it, vi } from "vitest";
import {
  ACTIVITY_DELETED,
  ACTIVITY_FAILED,
  ACTIVITY_IMPORT_COMPLETED,
  ACTIVITY_IMPORT_FAILED,
  ACTIVITY_PROCESSED,
  ACTIVITY_SEGMENTS_MATCHED,
  ACTIVITY_UPDATED,
  COMMENT_CREATED,
  COMMENT_DELETED,
  COMMENT_UPDATED,
  ITINERARY_DELETED,
  ITINERARY_SAVED,
  KUDOS_CHANGED,
  activityTopic,
  userTopic,
} from "@repo/realtime";
import type { RealtimePublisher } from "@repo/realtime";
import { RealtimeBridge } from "./realtime-bridge.listener.js";

function createFakePublisher(): RealtimePublisher & {
  publishRealtimeEvent: ReturnType<typeof vi.fn>;
} {
  return { publishRealtimeEvent: vi.fn().mockResolvedValue(undefined) };
}

describe("RealtimeBridge", () => {
  it("forwards activities.activity.processed as activity.processed on the user's topic", async () => {
    const publisher = createFakePublisher();
    const bridge = new RealtimeBridge(publisher);

    await bridge.onActivityProcessed({
      activityId: "act_1",
      userId: "user_1",
      status: "processed",
    });

    expect(publisher.publishRealtimeEvent).toHaveBeenCalledTimes(1);
    const [topics, type, data] = publisher.publishRealtimeEvent.mock.calls[0] as [
      string[],
      string,
      Record<string, unknown>,
    ];
    expect(topics).toEqual([userTopic("user_1")]);
    expect(type).toBe(ACTIVITY_PROCESSED);
    expect(data).toMatchObject({ activityId: "act_1", status: "processed" });
  });

  it("forwards activities.activity.failed as activity.failed", async () => {
    const publisher = createFakePublisher();
    const bridge = new RealtimeBridge(publisher);

    await bridge.onActivityFailed({ activityId: "act_1", userId: "user_1", status: "failed" });

    const [topics, type] = publisher.publishRealtimeEvent.mock.calls[0] as [string[], string];
    expect(topics).toEqual([userTopic("user_1")]);
    expect(type).toBe(ACTIVITY_FAILED);
  });

  it("forwards activities.activity.deleted as activity.deleted on the author's and the activity's topics, id only", async () => {
    const publisher = createFakePublisher();
    const bridge = new RealtimeBridge(publisher);

    await bridge.onActivityDeleted({ activityId: "act_1", userId: "user_1" });

    expect(publisher.publishRealtimeEvent).toHaveBeenCalledExactlyOnceWith(
      [userTopic("user_1"), activityTopic("act_1")],
      ACTIVITY_DELETED,
      { activityId: "act_1" },
    );
  });

  it("forwards activities.activity.updated as activity.updated on the author's and the activity's topics, with the changed fields", async () => {
    const publisher = createFakePublisher();
    const bridge = new RealtimeBridge(publisher);

    await bridge.onActivityUpdated({ activityId: "act_1", userId: "user_1", changedFields: ["title", "sportTypeCode"] });

    expect(publisher.publishRealtimeEvent).toHaveBeenCalledExactlyOnceWith(
      [userTopic("user_1"), activityTopic("act_1")],
      ACTIVITY_UPDATED,
      { activityId: "act_1", changedFields: ["title", "sportTypeCode"] },
    );
  });

  it.each([
    ["engagement.comment.added", "onCommentAdded", COMMENT_CREATED],
    ["engagement.comment.edited", "onCommentEdited", COMMENT_UPDATED],
    ["engagement.comment.deleted", "onCommentDeleted", COMMENT_DELETED],
  ] as const)("forwards %s through %s on the activity's topic only, ids only", async (_event, handler, type) => {
    const publisher = createFakePublisher();
    const bridge = new RealtimeBridge(publisher);

    await bridge[handler]({ commentId: "com_1", activityId: "act_1", userId: "user_1" });

    expect(publisher.publishRealtimeEvent).toHaveBeenCalledExactlyOnceWith([activityTopic("act_1")], type, {
      activityId: "act_1",
      commentId: "com_1",
    });
  });

  it.each([
    ["engagement.kudos.given", "onKudosGiven"],
    ["engagement.kudos.removed", "onKudosRemoved"],
  ] as const)("forwards %s as kudos.changed on the activity's topic, activity id only", async (_event, handler) => {
    const publisher = createFakePublisher();
    const bridge = new RealtimeBridge(publisher);

    await bridge[handler]({ activityId: "act_1", userId: "user_1" });

    expect(publisher.publishRealtimeEvent).toHaveBeenCalledExactlyOnceWith([activityTopic("act_1")], KUDOS_CHANGED, {
      activityId: "act_1",
    });
  });

  it("forwards segments.efforts.matched as activity.segments_matched", async () => {
    const publisher = createFakePublisher();
    const bridge = new RealtimeBridge(publisher);

    await bridge.onSegmentsEffortsMatched({ activityId: "act_1", userId: "user_1" });

    const [topics, type] = publisher.publishRealtimeEvent.mock.calls[0] as [string[], string];
    expect(topics).toEqual([userTopic("user_1")]);
    expect(type).toBe(ACTIVITY_SEGMENTS_MATCHED);
  });

  it("forwards activities.import.completed as activity_import.completed with the outcome", async () => {
    const publisher = createFakePublisher();
    const bridge = new RealtimeBridge(publisher);

    await bridge.onActivityImportCompleted({
      importId: "imp_1",
      activityId: "act_1",
      userId: "user_1",
      outcome: "duplicate",
    });

    const [topics, type, data] = publisher.publishRealtimeEvent.mock.calls[0] as [
      string[],
      string,
      Record<string, unknown>,
    ];
    expect(topics).toEqual([userTopic("user_1")]);
    expect(type).toBe(ACTIVITY_IMPORT_COMPLETED);
    expect(data).toMatchObject({ importId: "imp_1", activityId: "act_1", status: "duplicate" });
  });

  it("forwards activities.import.failed as activity_import.failed with the error code", async () => {
    const publisher = createFakePublisher();
    const bridge = new RealtimeBridge(publisher);

    await bridge.onActivityImportFailed({ importId: "imp_1", userId: "user_1", code: "no_gps_data" });

    const [, type, data] = publisher.publishRealtimeEvent.mock.calls[0] as [
      string[],
      string,
      Record<string, unknown>,
    ];
    expect(type).toBe(ACTIVITY_IMPORT_FAILED);
    expect(data).toMatchObject({ importId: "imp_1", status: "failed", code: "no_gps_data" });
  });

  it("forwards itineraries.itinerary.saved as itinerary.saved with its updatedAt only", async () => {
    const publisher = createFakePublisher();
    const bridge = new RealtimeBridge(publisher);

    await bridge.onItinerarySaved({ itineraryId: "itn_1", userId: "user_1", updatedAt: "2026-10-10T08:00:00.000Z" });

    expect(publisher.publishRealtimeEvent).toHaveBeenCalledExactlyOnceWith([userTopic("user_1")], ITINERARY_SAVED, {
      itineraryId: "itn_1",
      updatedAt: "2026-10-10T08:00:00.000Z",
    });
  });

  it("forwards itineraries.itinerary.deleted as itinerary.deleted", async () => {
    const publisher = createFakePublisher();
    const bridge = new RealtimeBridge(publisher);

    await bridge.onItineraryDeleted({ itineraryId: "itn_1", userId: "user_1" });

    expect(publisher.publishRealtimeEvent).toHaveBeenCalledExactlyOnceWith([userTopic("user_1")], ITINERARY_DELETED, {
      itineraryId: "itn_1",
    });
  });

  it("logs a warning and does not throw when the publisher fails", async () => {
    const publisher: RealtimePublisher = {
      publishRealtimeEvent: vi.fn().mockRejectedValue(new Error("redis down")),
    };
    const bridge = new RealtimeBridge(publisher);

    await expect(
      bridge.onActivityProcessed({ activityId: "act_1", userId: "user_1", status: "processed" }),
    ).resolves.toBeUndefined();
  });

  it("has no listener for an event outside the forwarding table", () => {
    const bridge = new RealtimeBridge(createFakePublisher());
    expect(
      (bridge as unknown as Record<string, unknown>)["onSomethingUnrelated"],
    ).toBeUndefined();
  });
});
