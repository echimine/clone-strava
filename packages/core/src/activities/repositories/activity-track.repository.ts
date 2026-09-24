import { Inject, Injectable, NotImplementedException } from "@nestjs/common";
import { schema, type Database } from "@repo/db";
import { DATABASE } from "../../infrastructure/index.js";

/** Reads and writes on `activities.activity_track` only (ADR-021 §6). */
@Injectable()
export class ActivityTrackRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  /** Upsert (ADR-019 §5 step 7), route already passed through the privacy zone. */
  async upsert(_values: typeof schema.activityTrack.$inferInsert): Promise<void> {
    throw new NotImplementedException();
  }
}
