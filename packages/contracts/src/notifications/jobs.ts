import { z } from "zod";
import { requestIdFieldSchema } from "../common/request-id.js";

/**
 * `emails` queue (ADR-038 §4, ADR-011): e-mails sent after the fact, through a job, so a Resend
 * outage never fails the action that triggered them. Enqueued with `EmailJobs.enqueue`
 * (`@repo/core/notifications`), run by `apps/worker`.
 */
export const EMAILS_QUEUE_NAME = "emails";
/** `send-email` job: renders one template and sends it, `CONTACT_EMAIL` as Reply-To. */
export const SEND_EMAIL_JOB_NAME = "send-email";

/**
 * Idempotency key of an e-mail: also Resend's, and the job id's suffix. A Sanction's is its
 * Journal entry id. No `:` (BullMQ 6 rejects it in a job id).
 */
export const emailIdempotencyKeySchema = z
  .string()
  .min(1)
  .max(200)
  .regex(/^[A-Za-z0-9._/-]+$/);

/** Deterministic job id (ADR-011 §2): one e-mail per idempotency key. */
export function sendEmailJobId(idempotencyKey: string): string {
  return `send-email-${idempotencyKey}`;
}

/** The recipient's first name, for « Bonjour Léa, »; null greets without a name. */
const firstNameSchema = z.string().min(1).nullable();
/** A Sanction's reason, as the Administrator typed it: the athlete reads it (ADR-038 §4). */
const reasonSchema = z.string().min(1);
/** An Activity as the athlete knew it, named without a link (« Sortie du dimanche » du 2 novembre). */
const activityLabelSchema = z.object({ title: z.string(), startedAt: z.iso.datetime() });
export type EmailActivityLabel = z.infer<typeof activityLabelSchema>;

/**
 * Ban (24 h, 7 days, 30 days or permanent): `until` is the Ban's end, null for « définitivement ».
 * Sent again when an athlete already banned is banned again.
 */
export const userBannedEmailSchema = z.object({
  firstName: firstNameSchema,
  reason: reasonSchema,
  until: z.iso.datetime().nullable(),
});

/** Ban lifted by an Administrator; never when a temporary Ban ends by itself. */
export const userUnbannedEmailSchema = z.object({ firstName: firstNameSchema, reason: reasonSchema });

/** What a « Contenu retiré » e-mail names: an Activity, one of its Media, its text, or a comment. */
export const removedContentSchema = z.discriminatedUnion("kind", [
  z.object({ kind: z.literal("activity"), activity: activityLabelSchema }),
  z.object({ kind: z.literal("media"), activity: activityLabelSchema }),
  /** Title and description reset: `activity` holds the title before the reset. */
  z.object({ kind: z.literal("activity-text"), activity: activityLabelSchema }),
  /** Quoted, truncated to about 200 characters; `activity` null if already gone. */
  z.object({
    kind: z.literal("comment"),
    body: z.string(),
    postedAt: z.iso.datetime().nullable(),
    activity: activityLabelSchema.nullable(),
  }),
]);
export type RemovedContent = z.infer<typeof removedContentSchema>;

export const contentRemovedEmailSchema = z.object({
  firstName: firstNameSchema,
  reason: reasonSchema,
  content: removedContentSchema,
});

/** Name, bio or Avatar reset to its default. */
export const profileResetEmailSchema = z.object({
  firstName: firstNameSchema,
  reason: reasonSchema,
  field: z.enum(["name", "bio", "avatar"]),
});

/**
 * « Votre compte Nervo a été supprimé » (ADR-038 §13), by the athlete or by an Administrator:
 * `reason` is the Sanction's, null when the athlete deleted it themselves (then no contact
 * line either).
 */
export const accountDeletedEmailSchema = z.object({
  firstName: firstNameSchema,
  reason: reasonSchema.nullable(),
});

/** Fields every `send-email` job carries, whatever its template. */
const sendEmailJobBaseShape = {
  to: z.email(),
  idempotencyKey: emailIdempotencyKeySchema,
  /** The athlete concerned, for the Jobs screen's link; null for an e-mail about no athlete. */
  userId: z.uuid().nullable(),
  requestId: requestIdFieldSchema,
};

/**
 * `send-email` payload: a template and the data it names, carried in the job because the
 * content or the account may be gone by the time it runs (ADR-038 §4). One branch per
 * template family; #213 (new report case) and #219 (Segment) add theirs here.
 */
export const sendEmailJobSchema = z.discriminatedUnion("template", [
  z.object({ template: z.literal("user-banned"), data: userBannedEmailSchema, ...sendEmailJobBaseShape }),
  z.object({ template: z.literal("user-unbanned"), data: userUnbannedEmailSchema, ...sendEmailJobBaseShape }),
  z.object({ template: z.literal("content-removed"), data: contentRemovedEmailSchema, ...sendEmailJobBaseShape }),
  z.object({ template: z.literal("profile-reset"), data: profileResetEmailSchema, ...sendEmailJobBaseShape }),
  z.object({ template: z.literal("account-deleted"), data: accountDeletedEmailSchema, ...sendEmailJobBaseShape }),
]);
export type SendEmailJob = z.infer<typeof sendEmailJobSchema>;
export type EmailTemplate = SendEmailJob["template"];
/** The data of `template`'s e-mail. */
export type EmailTemplateData<T extends EmailTemplate> = Extract<SendEmailJob, { template: T }>["data"];
