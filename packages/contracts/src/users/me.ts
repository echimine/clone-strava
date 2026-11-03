import { z } from "zod";
import { userRoleSchema, visibilitySchema } from "../common/enums.js";

/**
 * `GET /v1/me` response (ADR-009 §3, ADR-013): current user, role and premium
 * status, the visibility preselected for a new Activity (ADR-031 §13), and
 * "Approuver mes abonnés" (ADR-036 §1).
 */
export const meResponseSchema = z.object({
  id: z.uuid(),
  email: z.email(),
  name: z.string(),
  role: userRoleSchema,
  isPremium: z.boolean(),
  /** `user_profile.default_visibility`, `public` without a profile row. */
  defaultVisibility: visibilitySchema,
  /** `social.follow_settings.approve_followers`, `false` without a row. */
  approveFollowers: z.boolean(),
});
export type MeResponse = z.infer<typeof meResponseSchema>;
