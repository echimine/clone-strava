import { ForbiddenException, Injectable } from "@nestjs/common";
import { GetVisibleActivityUseCase } from "../use-cases/get-visible-activity.use-case.js";
import { activityNotFound } from "./activity-not-found.js";

/**
 * The Activity of its author, whatever its processing state (ADR-037 §4: the Media routes). Not
 * visible: `404 activity_not_found`; visible but someone else's: `403 not_activity_author`.
 */
@Injectable()
export class AuthorActivityResolver {
  constructor(private readonly getVisibleActivity: GetVisibleActivityUseCase) {}

  async resolve(userId: string, activityId: string) {
    const row = await this.getVisibleActivity.findRow(userId, activityId);
    if (!row) {
      throw activityNotFound();
    }
    if (row.userId !== userId) {
      throw new ForbiddenException({
        code: "not_activity_author",
        message: "Only the author can manage this activity's Media",
      });
    }
    return row;
  }
}
