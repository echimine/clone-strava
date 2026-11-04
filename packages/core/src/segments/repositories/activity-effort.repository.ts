import { Inject, Injectable } from "@nestjs/common";
import { asc, eq } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE } from "../../infrastructure/index.js";
import type { ActivityEffortRecord } from "../domain/activity-effort.js";

/** Reads an Activity's efforts on `segments.segment_effort` with their Segment's name (ADR-038 §11). */
@Injectable()
export class ActivityEffortRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  /** In the order they were ridden or run. */
  findByActivityId(activityId: string): Promise<ActivityEffortRecord[]> {
    const effort = schema.segmentEffort;
    return this.db
      .select({
        id: effort.id,
        segmentId: effort.segmentId,
        segmentName: schema.segment.name,
        elapsedTimeS: effort.elapsedTimeS,
        startedAt: effort.startedAt,
        rank: effort.rank,
      })
      .from(effort)
      .innerJoin(schema.segment, eq(schema.segment.id, effort.segmentId))
      .where(eq(effort.activityId, activityId))
      .orderBy(asc(effort.startedAt), asc(effort.id));
  }
}
