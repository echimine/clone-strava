import { Inject, Injectable, NotImplementedException } from "@nestjs/common";
import { eq } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE } from "../../infrastructure/index.js";

/**
 * Reads and writes on `subscriptions.revenuecat_event` only (ADR-021 §6),
 * deduplicated by RevenueCat's own event id (ADR-014 "Backend side").
 */
@Injectable()
export class RevenuecatEventRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  findById(id: string) {
    return this.db.query.revenuecatEvent.findFirst({
      where: eq(schema.revenuecatEvent.id, id),
    });
  }

  async record(_event: typeof schema.revenuecatEvent.$inferInsert): Promise<void> {
    throw new NotImplementedException();
  }
}
