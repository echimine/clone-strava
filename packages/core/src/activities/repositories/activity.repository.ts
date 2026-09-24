import { Inject, Injectable, NotImplementedException } from "@nestjs/common";
import { eq, inArray } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE } from "../../infrastructure/index.js";

/** Reads and writes on `activities.activity` only (ADR-021 §6). */
@Injectable()
export class ActivityRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  findById(id: string) {
    return this.db.query.activity.findFirst({ where: eq(schema.activity.id, id) });
  }

  findByIds(ids: string[]) {
    if (ids.length === 0) {
      return Promise.resolve([]);
    }
    return this.db.query.activity.findMany({ where: inArray(schema.activity.id, ids) });
  }

  findStuckProcessing(_olderThanMinutes: number) {
    // ADR-019 §7: `activity_processing_status_idx` (partial index, status != 'processed').
    throw new NotImplementedException();
  }

  async insert(_values: typeof schema.activity.$inferInsert): Promise<void> {
    throw new NotImplementedException();
  }

  async updateStatus(
    _id: string,
    _status: (typeof schema.processingStatusEnum.enumValues)[number],
  ): Promise<void> {
    throw new NotImplementedException();
  }
}
