import { z } from "zod";
import { feedAuthorSchema } from "../activities/feed.js";
import { userRoleSchema, visibilitySchema } from "../common/enums.js";
import { reportCaseStatusSchema, reportReasonSchema, reportTargetTypeSchema } from "../moderation/report.js";
import { athleteLevelSchema } from "../users/onboarding-answers.js";
import {
  adminListQuerySchema,
  adminListResponseSchema,
  adminPeriodShape,
  adminSortQuerySchema,
  isOrderedPeriod,
  periodOrderIssue,
} from "./list.js";
import { adminPremiumStateSchema, adminUserPremiumFilterSchema } from "./premium.js";
import { adminOptionalReasonSchema, adminReasonSchema } from "./reason.js";

/**
 * An account's state for the backoffice (ADR-038 §5, §6): `active` without an active Ban,
 * `banned` for a permanent one, `temporarily_banned` until its end date. A Ban whose end has
 * passed counts as over, even before the next sign-in clears the row.
 */
export const adminUserStateSchema = z.enum(["active", "banned", "temporarily_banned"]);
export type AdminUserState = z.infer<typeof adminUserStateSchema>;

/**
 * How an account signs in (ADR-035 §2): `google` when a Google account is linked, `email_code`
 * when it was created by Sign-in code (no Google link), `password` for the backoffice's
 * password accounts. Every address can still receive a Sign-in code.
 */
export const signInMethodSchema = z.enum(["email_code", "google", "password"]);
export type SignInMethod = z.infer<typeof signInMethodSchema>;

/** An account's sign-in methods from the `provider_id`s of its Better Auth `account` rows. */
export function signInMethodsFromProviders(providerIds: readonly string[]): SignInMethod[] {
  const hasGoogle = providerIds.includes("google");
  return [
    ...(hasGoogle ? [] : (["email_code"] as const)),
    ...(hasGoogle ? (["google"] as const) : []),
    ...(providerIds.includes("credential") ? (["password"] as const) : []),
  ];
}

/** The list's sign-in method filter: Sign-in code or Google. */
export const adminUserMethodFilterSchema = z.enum(["email_code", "google"]);

export const ADMIN_USER_SORT_FIELDS = ["createdAt", "lastActivityAt"] as const;

/**
 * `GET /v1/admin/users?q&role&state&premium&method&from&to&sort&order&page&pageSize`
 * (ADR-038 §5): `q` searches first name, last name and e-mail; `from`/`to` are Paris days of the
 * sign-up; `premium` is a Premium state (ADR-038 §12); sort by sign-up (default, newest first) or
 * last Activity.
 */
export const adminUserListQuerySchema = adminListQuerySchema
  .extend({
    ...adminSortQuerySchema(ADMIN_USER_SORT_FIELDS, { sort: "createdAt", order: "desc" }).shape,
    ...adminPeriodShape,
    role: userRoleSchema.optional(),
    state: adminUserStateSchema.optional(),
    premium: adminUserPremiumFilterSchema.optional(),
    method: adminUserMethodFilterSchema.optional(),
  })
  .refine(isOrderedPeriod, periodOrderIssue);
export type AdminUserListQuery = z.infer<typeof adminUserListQuerySchema>;

/** An active Ban: its end (null = permanent) and the reason the athlete reads. */
export const adminUserBanSchema = z.object({
  until: z.iso.datetime().nullable(),
  reason: z.string().nullable(),
});
export type AdminUserBan = z.infer<typeof adminUserBanSchema>;

/** One row of the backoffice users list. */
export const adminUserListItemSchema = z.object({
  athlete: feedAuthorSchema,
  email: z.string(),
  role: userRoleSchema,
  createdAt: z.iso.datetime(),
  signInMethods: z.array(signInMethodSchema),
  activityCount: z.number().int().nonnegative(),
  lastActivityAt: z.iso.datetime().nullable(),
  isPremium: z.boolean(),
  /** The Premium state (ADR-038 §12), as the sheet derives it. */
  premiumState: adminPremiumStateSchema,
  /** The « Fin » column: the end of the Premium period (grace period included); null without one. */
  premiumEndsAt: z.iso.datetime().nullable(),
  state: adminUserStateSchema,
  /** The active Ban, if any (« Banni jusqu'au … »). */
  ban: adminUserBanSchema.nullable(),
});
export type AdminUserListItem = z.infer<typeof adminUserListItemSchema>;

export const adminUserListResponseSchema = adminListResponseSchema(adminUserListItemSchema);
export type AdminUserListResponse = z.infer<typeof adminUserListResponseSchema>;

/**
 * `GET /v1/admin/users/:id` (ADR-038 §5): the sheet's sections 1 to 5. The athlete profile
 * **never** carries the birth date, gender or weight. Sessions, Reports, Premium
 * (`GET :id/premium`) and the Historique have their own reads.
 */
export const adminUserDetailSchema = z.object({
  athlete: feedAuthorSchema,
  email: z.string(),
  role: userRoleSchema,
  createdAt: z.iso.datetime(),
  state: adminUserStateSchema,
  ban: adminUserBanSchema.nullable(),
  premium: z.object({
    active: z.boolean(),
    /** An App Store subscription that renews: Apple keeps billing a banned athlete. */
    billedByAppStore: z.boolean(),
  }),
  account: z.object({
    signInMethods: z.array(signInMethodSchema),
    /** Relevant for Administrators (ADR-022 §5). */
    twoFactorEnabled: z.boolean(),
  }),
  profile: z.object({
    firstName: z.string().nullable(),
    lastName: z.string().nullable(),
    bio: z.string().nullable(),
    city: z.string().nullable(),
    country: z.string().nullable(),
    /** Practiced sports, in the athlete's order. */
    sports: z.array(z.string()),
    level: athleteLevelSchema.nullable(),
    defaultVisibility: visibilitySchema,
  }),
  activity: z.object({
    activityCount: z.number().int().nonnegative(),
    lastActivityAt: z.iso.datetime().nullable(),
    streakWeeks: z.number().int().nonnegative(),
  }),
  follows: z.object({
    followerCount: z.number().int().nonnegative(),
    followingCount: z.number().int().nonnegative(),
    /** « Bloqué par N athlètes » (ADR-038 §8). */
    blockedByCount: z.number().int().nonnegative(),
  }),
});
export type AdminUserDetail = z.infer<typeof adminUserDetailSchema>;

/** An open session: device from its user agent, opening and expiry. Never the token nor the IP. */
export const adminUserSessionSchema = z.object({
  id: z.string(),
  /** « iPhone (app Nervo) », « Chrome sur macOS »…; null without a user agent. */
  device: z.string().nullable(),
  userAgent: z.string().nullable(),
  createdAt: z.iso.datetime(),
  expiresAt: z.iso.datetime(),
});
export type AdminUserSession = z.infer<typeof adminUserSessionSchema>;

/** `GET /v1/admin/users/:id/sessions` (ADR-038 §5), newest first. */
export const adminUserSessionsResponseSchema = z.object({ items: z.array(adminUserSessionSchema) });
export type AdminUserSessionsResponse = z.infer<typeof adminUserSessionsResponseSchema>;

/** A Report as the user sheet lists it: reason, date, its case's status and link (`/reports/<caseId>`). */
export const adminUserReportSchema = z.object({
  id: z.uuid(),
  caseId: z.uuid(),
  targetType: reportTargetTypeSchema,
  reason: reportReasonSchema,
  status: reportCaseStatusSchema,
  createdAt: z.iso.datetime(),
});
export type AdminUserReport = z.infer<typeof adminUserReportSchema>;

/** The most Reports each tab lists, newest first. */
export const ADMIN_USER_REPORTS_LIMIT = 100;

/**
 * `GET /v1/admin/users/:id/reports` (ADR-038 §5): the sheet's « Signalements » tabs. `received`:
 * Reports on the athlete or their content; `sent`: Reports the athlete made.
 */
export const adminUserReportsResponseSchema = z.object({
  received: z.array(adminUserReportSchema),
  sent: z.array(adminUserReportSchema),
});
export type AdminUserReportsResponse = z.infer<typeof adminUserReportsResponseSchema>;

/** A Ban's closed choice of duration (ADR-038 §5): banning again replaces it. */
export const banDurationSchema = z.enum(["24h", "7d", "30d", "permanent"]);
export type BanDuration = z.infer<typeof banDurationSchema>;

/** Seconds of each temporary Ban duration. */
export const BAN_DURATION_SECONDS: Record<Exclude<BanDuration, "permanent">, number> = {
  "24h": 24 * 3600,
  "7d": 7 * 24 * 3600,
  "30d": 30 * 24 * 3600,
};

/** `POST /v1/admin/users/:id/ban` (Sanction, reason required). */
export const adminBanBodySchema = z.object({ duration: banDurationSchema, reason: adminReasonSchema });
export type AdminBanBody = z.infer<typeof adminBanBodySchema>;

/** `PUT /v1/admin/users/:id/role` (not a Sanction, optional reason). */
export const adminRoleBodySchema = z.object({ role: userRoleSchema, reason: adminOptionalReasonSchema });
export type AdminRoleBody = z.infer<typeof adminRoleBodySchema>;

/**
 * `409` codes of the users area (ADR-038 §5): an Administrator can be neither banned nor deleted
 * before being demoted; nobody demotes themself nor the last Administrator.
 */
export const ADMIN_USER_ERROR_CODES = {
  userIsAdmin: "user_is_admin",
  cannotDemoteSelf: "cannot_demote_self",
  lastAdmin: "last_admin",
  roleUnchanged: "role_unchanged",
  notBanned: "not_banned",
} as const;
