import type { AuditAction } from "@repo/contracts";

/** Metadata key of `@Audited` on a route handler. */
export const AUDITED_METADATA = "admin:audited";

/** Where the interceptor keeps the draft entry on the request. */
export const AUDIT_DRAFT = Symbol("auditDraft");

export interface AuditedOptions {
  /** Whether `body.reason` is required (a Sanction), optional, or not read at all. */
  reason: "required" | "optional" | "none";
  /** Route parameter holding the target id; `"id"` by default, `null` when the route has none. */
  targetParam?: string | null;
}

export interface AuditedMetadata extends AuditedOptions {
  action: AuditAction;
}

/** What the handler may add to its entry (ADR-038 §3: "le handler peut compléter"). */
export interface AuditDraft {
  /** The id the entry will be written with. */
  readonly entryId: string;
  /**
   * The action actually done, when one route serves two of them with the same target type:
   * `PUT /v1/admin/users/:id/role` is declared `user.role.grant` and records `user.role.revoke`
   * for a demotion.
   */
  action?: AuditAction;
  /** The athlete concerned (the author of a removed comment, for example). */
  subjectUserId?: string | null;
  /** Overrides the target id read from the route. */
  targetId?: string | null;
  /** The action's parameters only (a Ban's duration, a batch's count and ids), never content. */
  details?: Record<string, unknown>;
  /**
   * The reason to record when the body names it otherwise: a report case's closing `note`
   * (ADR-038 §17, `report.resolve` / `report.dismiss`, optional). Such a route is declared
   * `reason: "optional"`; on a route declared `"none"` it is not recorded (an error is logged).
   */
  reason?: string | null;
}
