import { z } from "zod";
import { userRoleSchema, visibilitySchema } from "../common/enums.js";

/**
 * `GET /v1/me` response (ADR-009 §3, ADR-013): current user, role and premium
 * status, and the visibility preselected for a new Activity (ADR-031 §13).
 */
export const meResponseSchema = z.object({
  id: z.uuid(),
  email: z.email(),
  name: z.string(),
  role: userRoleSchema,
  isPremium: z.boolean(),
  /** `user_profile.default_visibility`, `public` without a profile row. */
  defaultVisibility: visibilitySchema,
});
export type MeResponse = z.infer<typeof meResponseSchema>;
