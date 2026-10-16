import { Injectable, NotFoundException, UnprocessableEntityException } from "@nestjs/common";
import { EventEmitter2 } from "@nestjs/event-emitter";
import { KUDOS_GIVEN_EVENT, KUDOS_REMOVED_EVENT, type KudosEvent } from "@repo/contracts";
import { ActivitiesService } from "../../activities/index.js";
import { KudosRepository } from "../repositories/kudos.repository.js";
import type { KudosState } from "../domain/kudos-state.js";

/**
 * Gives or removes kudos on an activity (ADR-017, ADR-029). Checks the
 * target activity is visible to the user through `ActivitiesService`
 * (ADR-021 §2: `engagement` may depend on `activities`), never a direct
 * table read. Both directions are idempotent, and emit
 * `engagement.kudos.given` / `removed` after the write only when the state
 * actually changed (ADR-034 §4).
 */
@Injectable()
export class GiveKudosUseCase {
  constructor(
    private readonly activities: ActivitiesService,
    private readonly kudos: KudosRepository,
    private readonly events: EventEmitter2,
  ) {}

  async execute(userId: string, activityId: string): Promise<KudosState> {
    await this.assertCanKudos(userId, activityId);
    if (await this.kudos.give(userId, activityId)) {
      this.events.emit(KUDOS_GIVEN_EVENT, { activityId, userId } satisfies KudosEvent);
    }
    return this.state(activityId, true);
  }

  async remove(userId: string, activityId: string): Promise<KudosState> {
    await this.assertCanKudos(userId, activityId);
    if (await this.kudos.remove(userId, activityId)) {
      this.events.emit(KUDOS_REMOVED_EVENT, { activityId, userId } satisfies KudosEvent);
    }
    return this.state(activityId, false);
  }

  private async assertCanKudos(userId: string, activityId: string): Promise<void> {
    const activity = await this.activities.getVisible(userId, activityId);
    if (!activity) {
      throw new NotFoundException({ code: "activity_not_found", message: "Activity not found" });
    }
    if (activity.userId === userId) {
      throw new UnprocessableEntityException({
        code: "cannot_kudos_own_activity",
        message: "You cannot give kudos to your own activity",
      });
    }
  }

  private async state(activityId: string, viewerHasKudoed: boolean): Promise<KudosState> {
    const counts = await this.kudos.countByActivityIds([activityId]);
    return { activityId, kudosCount: counts.get(activityId) ?? 0, viewerHasKudoed };
  }
}
