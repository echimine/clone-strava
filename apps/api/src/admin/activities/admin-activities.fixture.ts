import { randomUUID } from "node:crypto";
import { ActivitiesModule } from "@repo/core/activities";
import { EngagementModule } from "@repo/core/engagement";
import { ModerationModule } from "@repo/core/moderation";
import { SegmentsModule } from "@repo/core/segments";
import { UsersModule } from "@repo/core/users";
import { AthleteIdentities } from "../../identities/athlete-identities.js";
import { MediaAssembler } from "../../media/media-assembler.js";
import { bootstrapAdminTestApp, type AdminTestApp } from "../../testing/admin-test-app.js";
import { AuditEntriesController } from "../audit/audit-entries.controller.js";
import { AuditEntryAssembler } from "../audit/audit-entry-assembler.js";
import { AdminCommentsController } from "../comments/admin-comments.controller.js";
import { SanctionNotices } from "../sanctions/sanction-notices.js";
import { AdminActivitiesController } from "./admin-activities.controller.js";
import { AdminActivityAssembler } from "./admin-activity-assembler.js";

export interface SeededActivity {
  userId: string;
  title?: string;
  description?: string | null;
  status?: "pending" | "processing" | "processed" | "failed";
  source?: "recorded" | "imported" | "manual";
  sport?: string;
  visibility?: "public" | "followers" | "private";
  startedAt?: string;
  createdAt?: string;
  error?: string | null;
}

export interface JournalRow {
  id: string;
  actor_id: string;
  target_type: string;
  target_id: string;
  subject_user_id: string | null;
  reason: string | null;
}

/** The backoffice Activities screen's test app (ADR-038 §11), its people and seeding helpers. */
export interface AdminActivitiesFixture {
  t: AdminTestApp;
  admin: string;
  emile: string;
  zoe: string;
  /** A tag on every seeded title, so a list only sees this file's Activities. */
  tag: string;
  seedActivity(values: SeededActivity): Promise<string>;
  /** The Journal entries of `action` on `targetId`. */
  journal(action: string, targetId: string): Promise<JournalRow[]>;
}

/** Boots the Activities and comments admin routes, the Journal's, and seeds an admin and two athletes. */
export async function bootstrapAdminActivities(): Promise<AdminActivitiesFixture> {
  const t = await bootstrapAdminTestApp({
    imports: [ActivitiesModule, EngagementModule, ModerationModule, SegmentsModule, UsersModule],
    controllers: [AdminActivitiesController, AdminCommentsController, AuditEntriesController],
    providers: [
      AdminActivityAssembler, AthleteIdentities, MediaAssembler, AuditEntryAssembler,
      // The e-mail hook is covered by `sanction-notices.spec.ts`: here only the notice handed over.
      { provide: SanctionNotices, useValue: { send: async () => undefined } },
    ],
  });
  const tag = `t${randomUUID().slice(0, 8)}`;

  async function seedActivity(values: SeededActivity): Promise<string> {
    const id = randomUUID();
    const startedAt = values.startedAt ?? "2026-11-02T08:00:00Z";
    await t.sql(
      `insert into activities.activity
         (id, user_id, sport_type_code, title, description, started_at, ended_at, visibility,
          processing_status, source, processing_error, processing_attempts, created_at, updated_at)
       values ($1, $2, $3, $4, $5, $6, $6::timestamptz + interval '1 hour', $7, $8, $9, $10, 2, $11, $11)`,
      [
        id,
        values.userId,
        values.sport ?? "run",
        values.title ?? `Sortie ${tag}`,
        values.description ?? null,
        startedAt,
        values.visibility ?? "public",
        values.status ?? "processed",
        values.source ?? "recorded",
        values.error ?? null,
        values.createdAt ?? new Date().toISOString(),
      ],
    );
    return id;
  }

  return {
    t,
    admin: await t.seedUser("Alice Admin", { role: "admin" }),
    emile: await t.seedUser("Émile Durand"),
    zoe: await t.seedUser("Zoé Martin"),
    tag,
    seedActivity,
    journal: (action, targetId) =>
      t.sql<JournalRow>("select * from audit.admin_audit_entry where action = $1 and target_id = $2", [action, targetId]),
  };
}

export const errorCode = async (response: Response) =>
  ((await response.json()) as { error: { code: string } }).error.code;
