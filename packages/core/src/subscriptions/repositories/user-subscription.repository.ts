import { Inject, Injectable } from "@nestjs/common";
import { and, eq } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE } from "../../infrastructure/index.js";

/** Reads and writes on `subscriptions.user_subscription` only (ADR-021 §6). */
@Injectable()
export class UserSubscriptionRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  findPremiumRow(userId: string) {
    return this.db.query.userSubscription.findFirst({
      where: and(
        eq(schema.userSubscription.userId, userId),
        eq(schema.userSubscription.entitlementId, "premium"),
      ),
    });
  }
}
