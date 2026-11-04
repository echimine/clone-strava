import { z } from "zod";

/**
 * Domain events of the `auth` module (ADR-021 §3), emitted by its Better Auth hooks after the
 * user row is written, IDs only. `apps/api` turns them into audit entries (ADR-038 §3): `auth`
 * and `audit` are both layer 0, so neither imports the other.
 */

/**
 * An Administrator turned their two-factor authentication on or off (ADR-022 §5). Emitted only
 * for an account whose role is `admin`, and only when the flag really changed.
 */
export const AUTH_ADMIN_TWO_FACTOR_CHANGED_EVENT = "auth.admin.two_factor_changed";
export const authAdminTwoFactorChangedEventSchema = z.object({
  userId: z.uuid(),
  enabled: z.boolean(),
});
export type AuthAdminTwoFactorChangedEvent = z.infer<typeof authAdminTwoFactorChangedEventSchema>;

/**
 * The `admin` role was granted or removed outside the backoffice: through Better Auth's own
 * `/api/auth/admin/*` routes. A change the API makes itself (`auth.api.setRole` from
 * `PUT /v1/admin/users/:id/role`) is recorded by that route and emits nothing.
 * `actorId` is whoever's session made the change, if any.
 */
export const AUTH_ADMIN_ROLE_CHANGED_EVENT = "auth.admin.role_changed";
export const authAdminRoleChangedEventSchema = z.object({
  userId: z.uuid(),
  actorId: z.uuid().nullable(),
  granted: z.boolean(),
});
export type AuthAdminRoleChangedEvent = z.infer<typeof authAdminRoleChangedEventSchema>;
