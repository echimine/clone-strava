import { Inject, Injectable } from "@nestjs/common";
import { and, count, desc, eq, gte, isNotNull, lt, type SQL } from "drizzle-orm";
import type { AuditAction, AuditTargetType } from "@repo/contracts";
import { schema, type Database } from "@repo/db";
import { DATABASE, offsetPage, parisDayRange } from "../../infrastructure/index.js";
import type { AuditEntryFilter, AuditEntryRecord } from "../domain/audit-entry.js";

type Row = typeof schema.adminAuditEntry.$inferSelect;

/** Reads and appends `audit.admin_audit_entry` (ADR-038 §3). Never updates nor deletes. */
@Injectable()
export class AdminAuditEntryRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  async insert(entry: typeof schema.adminAuditEntry.$inferInsert): Promise<string> {
    const [row] = await this.db
      .insert(schema.adminAuditEntry)
      .values(entry)
      .returning({ id: schema.adminAuditEntry.id });
    return row!.id;
  }

  /** One page, newest first, and the number of matching entries. */
  async findPage(
    filter: AuditEntryFilter,
    page: { page: number; pageSize: number },
  ): Promise<{ rows: AuditEntryRecord[]; total: number }> {
    const where = and(...this.conditions(filter));
    const { limit, offset } = offsetPage(page);
    const [rows, [counted]] = await Promise.all([
      this.db
        .select()
        .from(schema.adminAuditEntry)
        .where(where)
        .orderBy(desc(schema.adminAuditEntry.createdAt), desc(schema.adminAuditEntry.id))
        .limit(limit)
        .offset(offset),
      this.db.select({ total: count() }).from(schema.adminAuditEntry).where(where),
    ]);
    return { rows: rows.map(toRecord), total: counted?.total ?? 0 };
  }

  /** Everyone who authored at least one entry. */
  async findActorIds(): Promise<string[]> {
    const rows = await this.db
      .selectDistinct({ actorId: schema.adminAuditEntry.actorId })
      .from(schema.adminAuditEntry)
      .where(isNotNull(schema.adminAuditEntry.actorId));
    return rows.map((row) => row.actorId!);
  }

  private conditions(filter: AuditEntryFilter): SQL[] {
    const t = schema.adminAuditEntry;
    const { start, end } = parisDayRange(filter);
    return [
      filter.actorId ? eq(t.actorId, filter.actorId) : undefined,
      filter.action ? eq(t.action, filter.action) : undefined,
      filter.subjectUserId ? eq(t.subjectUserId, filter.subjectUserId) : undefined,
      start ? gte(t.createdAt, start) : undefined,
      end ? lt(t.createdAt, end) : undefined,
    ].filter((condition): condition is SQL => condition !== undefined);
  }
}

function toRecord(row: Row): AuditEntryRecord {
  return {
    id: row.id,
    createdAt: row.createdAt,
    actorId: row.actorId,
    action: row.action as AuditAction,
    targetType: row.targetType as AuditTargetType,
    targetId: row.targetId,
    subjectUserId: row.subjectUserId,
    reason: row.reason,
    details: row.details ?? null,
    requestId: row.requestId,
  };
}
