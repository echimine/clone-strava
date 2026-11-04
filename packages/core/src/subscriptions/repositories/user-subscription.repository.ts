import { Inject, Injectable } from "@nestjs/common";
import { and, eq } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE } from "../../infrastructure/index.js";
import type { PremiumMirror } from "../domain/premium-mirror.js";

/** The `premium` entitlement's row (ADR-017): one per athlete. */
const PREMIUM = "premium";

/** Reads and writes on `subscriptions.user_subscription` only (ADR-021 §6). */
@Injectable()
export class UserSubscriptionRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  findPremiumRow(userId: string) {
    return this.db.query.userSubscription.findFirst({
      where: and(
        eq(schema.userSubscription.userId, userId),
        eq(schema.userSubscription.entitlementId, PREMIUM),
      ),
    });
  }

  /**
   * Writes the `premium` row as RevenueCat computes it (ADR-038 §12). `sync-subscription` is the
   * only caller: nothing else writes `user_subscription`. An account deleted meanwhile is skipped.
   */
  async upsertPremium(userId: string, mirror: PremiumMirror, syncedAt: Date): Promise<void> {
    const values = { ...mirror, syncedAt };
    try {
      await this.db
        .insert(schema.userSubscription)
        .values({ userId, entitlementId: PREMIUM, ...values })
        .onConflictDoUpdate({
          target: [schema.userSubscription.userId, schema.userSubscription.entitlementId],
          set: values,
        });
    } catch (error) {
      if (!isForeignKeyViolation(error)) {
        throw error;
      }
    }
  }
}

/** Postgres `23503`: the user row is gone (account deleted). */
export function isForeignKeyViolation(error: unknown): boolean {
  for (let cause: unknown = error; cause instanceof Error; cause = cause.cause) {
    if ((cause as { code?: unknown }).code === "23503") {
      return true;
    }
  }
  return false;
}
