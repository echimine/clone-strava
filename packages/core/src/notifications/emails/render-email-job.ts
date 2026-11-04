import type { SendEmailJob } from "@repo/contracts";
import { ACCOUNT_DELETED_SUBJECT, renderAccountDeletedEmail } from "./account-deleted-email.js";
import { CONTENT_REMOVED_SUBJECT, renderContentRemovedEmail } from "./content-removed-email.js";
import { PROFILE_RESET_SUBJECT, renderProfileResetEmail } from "./profile-reset-email.js";
import { USER_BANNED_SUBJECT, renderUserBannedEmail } from "./user-banned-email.js";
import { USER_UNBANNED_SUBJECT, renderUserUnbannedEmail } from "./user-unbanned-email.js";

/** What every template needs besides its data: the wordmark and the team's address. */
export interface EmailRenderContext {
  /** `emailWordmarkUrl(adminOrigin)`. */
  logoUrl: string;
  /** `CONTACT_EMAIL`, null when not configured. */
  contactEmail: string | null;
}

export interface RenderedEmail {
  subject: string;
  html: string;
}

/** The subject and HTML of a `send-email` job's template (ADR-038 §4). */
export async function renderEmailJob(job: SendEmailJob, context: EmailRenderContext): Promise<RenderedEmail> {
  switch (job.template) {
    case "user-banned":
      return { subject: USER_BANNED_SUBJECT, html: await renderUserBannedEmail({ ...context, ...job.data }) };
    case "user-unbanned":
      return { subject: USER_UNBANNED_SUBJECT, html: await renderUserUnbannedEmail({ ...context, ...job.data }) };
    case "content-removed":
      return { subject: CONTENT_REMOVED_SUBJECT, html: await renderContentRemovedEmail({ ...context, ...job.data }) };
    case "profile-reset":
      return { subject: PROFILE_RESET_SUBJECT, html: await renderProfileResetEmail({ ...context, ...job.data }) };
    case "account-deleted":
      return { subject: ACCOUNT_DELETED_SUBJECT, html: await renderAccountDeletedEmail({ ...context, ...job.data }) };
  }
}
