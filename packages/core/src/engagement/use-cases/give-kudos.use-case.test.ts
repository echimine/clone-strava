import { NotFoundException, UnprocessableEntityException } from "@nestjs/common";
import { describe, expect, it, vi } from "vitest";
import { GiveKudosUseCase } from "./give-kudos.use-case.js";

const VIEWER = "11111111-1111-4111-8111-111111111111";
const OWNER = "22222222-2222-4222-8222-222222222222";
const ACTIVITY = "33333333-3333-4333-8333-333333333333";

function setup(visible: { userId: string } | null) {
  const activities = { getVisible: vi.fn().mockResolvedValue(visible && { id: ACTIVITY, ...visible }) };
  const kudos = {
    give: vi.fn(),
    remove: vi.fn(),
    countByActivityIds: vi.fn().mockResolvedValue(new Map([[ACTIVITY, 4]])),
  };
  return { useCase: new GiveKudosUseCase(activities as never, kudos as never), kudos };
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

  it("answers 404 for an activity the viewer cannot see", async () => {
    const { useCase, kudos } = setup(null);
    await expect(useCase.execute(VIEWER, ACTIVITY)).rejects.toBeInstanceOf(NotFoundException);
    expect(kudos.give).not.toHaveBeenCalled();
  });

  it("refuses kudos on one's own activity", async () => {
    const { useCase } = setup({ userId: VIEWER });
    await expect(useCase.execute(VIEWER, ACTIVITY)).rejects.toBeInstanceOf(UnprocessableEntityException);
  });
});
