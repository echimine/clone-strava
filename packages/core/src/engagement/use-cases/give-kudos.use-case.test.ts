import { NotFoundException, UnprocessableEntityException } from "@nestjs/common";
import { describe, expect, it, vi } from "vitest";
import { KUDOS_GIVEN_EVENT, KUDOS_REMOVED_EVENT } from "@repo/contracts";
import { GiveKudosUseCase } from "./give-kudos.use-case.js";

const VIEWER = "11111111-1111-4111-8111-111111111111";
const OWNER = "22222222-2222-4222-8222-222222222222";
const ACTIVITY = "33333333-3333-4333-8333-333333333333";

/** `changed`: whether the repository reports that the write changed the kudos state. */
function setup(visible: { userId: string } | null, changed = true) {
  const activities = { getVisible: vi.fn().mockResolvedValue(visible && { id: ACTIVITY, ...visible }) };
  const kudos = {
    give: vi.fn().mockResolvedValue(changed),
    remove: vi.fn().mockResolvedValue(changed),
    countByActivityIds: vi.fn().mockResolvedValue(new Map([[ACTIVITY, 4]])),
  };
  const events = { emit: vi.fn() };
  return { useCase: new GiveKudosUseCase(activities as never, kudos as never, events as never), kudos, events };
}

describe("GiveKudosUseCase", () => {
  it("gives kudos and returns the authoritative count", async () => {
    const { useCase, kudos } = setup({ userId: OWNER });
    expect(await useCase.execute(VIEWER, ACTIVITY)).toEqual({
      activityId: ACTIVITY,
      kudosCount: 4,
      viewerHasKudoed: true,
    });
    expect(kudos.give).toHaveBeenCalledWith(VIEWER, ACTIVITY);
  });

  it("removes kudos", async () => {
    const { useCase, kudos } = setup({ userId: OWNER });
    expect((await useCase.remove(VIEWER, ACTIVITY)).viewerHasKudoed).toBe(false);
    expect(kudos.remove).toHaveBeenCalledWith(VIEWER, ACTIVITY);
  });

  it("emits engagement.kudos.given / removed when the state changes (ADR-034 §4)", async () => {
    const { useCase, events } = setup({ userId: OWNER }, true);
    await useCase.execute(VIEWER, ACTIVITY);
    await useCase.remove(VIEWER, ACTIVITY);
    expect(events.emit.mock.calls).toEqual([
      [KUDOS_GIVEN_EVENT, { activityId: ACTIVITY, userId: VIEWER }],
      [KUDOS_REMOVED_EVENT, { activityId: ACTIVITY, userId: VIEWER }],
    ]);
  });

  it("emits nothing for a repeated give or remove", async () => {
    const { useCase, events } = setup({ userId: OWNER }, false);
    await useCase.execute(VIEWER, ACTIVITY);
    await useCase.remove(VIEWER, ACTIVITY);
    expect(events.emit).not.toHaveBeenCalled();
  });

  it("answers 404 for an activity the viewer cannot see", async () => {
    const { useCase, kudos, events } = setup(null);
    await expect(useCase.execute(VIEWER, ACTIVITY)).rejects.toBeInstanceOf(NotFoundException);
    expect(kudos.give).not.toHaveBeenCalled();
    expect(events.emit).not.toHaveBeenCalled();
  });

  it("refuses kudos on one's own activity", async () => {
    const { useCase } = setup({ userId: VIEWER });
    await expect(useCase.execute(VIEWER, ACTIVITY)).rejects.toBeInstanceOf(UnprocessableEntityException);
  });
});
