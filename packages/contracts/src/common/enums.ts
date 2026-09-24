import { z } from "zod";

/**
 * Enums mirroring the PostgreSQL `enum` types of `packages/db` (ADR-017).
 * Kept here, in `common`, since several modules share the same enum (e.g.
 * `visibility` is used by both `users` and `activities`).
 */

/** `activity.visibility`, `user_profile.default_visibility` (ADR-017). */
export const visibilitySchema = z.enum(["public", "followers", "private"]);
export type Visibility = z.infer<typeof visibilitySchema>;

/** `activity.processing_status` (ADR-017, ADR-019). */
export const processingStatusSchema = z.enum(["pending", "processing", "processed", "failed"]);
export type ProcessingStatus = z.infer<typeof processingStatusSchema>;

/** `user_profile.unit_system` (ADR-017). */
export const unitSystemSchema = z.enum(["metric", "imperial"]);
export type UnitSystem = z.infer<typeof unitSystemSchema>;

/** `follow.status` (ADR-017). */
export const followStatusSchema = z.enum(["pending", "accepted"]);
export type FollowStatus = z.infer<typeof followStatusSchema>;

/** `activity_attachment.kind` (ADR-017). */
export const attachmentKindSchema = z.enum(["photo", "video"]);
export type AttachmentKind = z.infer<typeof attachmentKindSchema>;

/** `sport_type.pace_unit` (ADR-017): whether the sport is displayed as a pace or a speed. */
export const paceUnitSchema = z.enum(["pace", "speed"]);
export type PaceUnit = z.infer<typeof paceUnitSchema>;

/** `user_subscription.store` (ADR-017, ADR-014). */
export const subscriptionStoreSchema = z.enum(["app_store"]);
export type SubscriptionStore = z.infer<typeof subscriptionStoreSchema>;

/** `user_subscription.period_type` (ADR-017). */
export const subscriptionPeriodTypeSchema = z.enum(["trial", "intro", "normal"]);
export type SubscriptionPeriodType = z.infer<typeof subscriptionPeriodTypeSchema>;

/** `user_subscription.environment` (ADR-017, ADR-014). */
export const subscriptionEnvironmentSchema = z.enum(["sandbox", "production"]);
export type SubscriptionEnvironment = z.infer<typeof subscriptionEnvironmentSchema>;

/** `user.role` (ADR-017, Better Auth admin plugin). */
export const userRoleSchema = z.enum(["user", "admin"]);
export type UserRole = z.infer<typeof userRoleSchema>;
