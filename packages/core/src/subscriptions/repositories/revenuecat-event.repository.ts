import { Inject, Injectable } from "@nestjs/common";
import { and, desc, eq, isNull, lte, sql } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE } from "../../infrastructure/index.js";

const event = schema.revenuecatEvent;
/** A field of the stored event, whether the payload is the webhook body (`{ event }`) or the event. */
const field = (name: string) => sql<string | null>`coalesce(${event.payload}->'event', ${event.payload})->>${name}`;

/** One RevenueCat event of an athlete, as the user sheet's history lists it (never the raw JSON). */
export interface PremiumEventRow {
  id: string;
  type: string;
  occurredAt: Date;
  productId: string | null;
  store: string | null;
  periodType: string | null;
  expiresAt: Date | null;
  sandbox: boolean;
}

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

  /**
   * Stores a webhook event once. Returns false for a delivery already stored, or for an athlete
   * we do not know (a deleted account: the event is ignored, ADR-038 §13).
   */
  async record(row: { id: string; userId: string; type: string; payload: unknown }): Promise<boolean> {
    const result = await this.db.execute<{ id: string }>(sql`
      insert into ${event} (id, user_id, type, payload)
      select ${row.id}, ${row.userId}, ${row.type}, ${JSON.stringify(row.payload)}::jsonb
      where exists (select 1 from ${schema.user} where ${schema.user.id} = ${row.userId})
      on conflict (id) do nothing
      returning id`);
    return result.rows.length > 0;
  }

  /** The athlete's events, newest first. */
  async listForUser(userId: string, limit: number): Promise<PremiumEventRow[]> {
    const occurredMs = field("event_timestamp_ms");
    const expirationMs = field("expiration_at_ms");
    const rows = await this.db
      .select({
        id: event.id,
        type: event.type,
        occurredMs,
        receivedAt: event.receivedAt,
        productId: field("product_id"),
        store: field("store"),
        periodType: field("period_type"),
        expirationMs,
        environment: field("environment"),
      })
      .from(event)
      .where(eq(event.userId, userId))
      .orderBy(desc(sql`coalesce(to_timestamp((${occurredMs})::double precision / 1000), ${event.receivedAt})`), desc(event.id))
      .limit(limit);
    return rows.map((row) => ({
      id: row.id,
      type: row.type,
      occurredAt: fromMs(row.occurredMs) ?? row.receivedAt,
      productId: row.productId,
      store: row.store,
      periodType: row.periodType,
      expiresAt: fromMs(row.expirationMs),
      sandbox: row.environment?.toUpperCase() === "SANDBOX",
    }));
  }

  /** Marks the athlete's events received up to `until` as handled by a sync. */
  async markProcessed(userId: string, until: Date): Promise<void> {
    await this.db
      .update(event)
      .set({ processedAt: sql`now()` })
      .where(and(eq(event.userId, userId), isNull(event.processedAt), lte(event.receivedAt, until)));
  }
}

function fromMs(value: string | null): Date | null {
  const ms = value === null ? Number.NaN : Number(value);
  return Number.isFinite(ms) ? new Date(ms) : null;
}
