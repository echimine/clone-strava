import { z } from "zod";
import { userRoleSchema } from "../common/enums.js";

/** `GET /v1/me` response (ADR-009 §3, ADR-013): current user, role and premium status. */
export const meResponseSchema = z.object({
  id: z.uuid(),
  email: z.email(),
  name: z.string(),
  role: userRoleSchema,
  isPremium: z.boolean(),
});
export type MeResponse = z.infer<typeof meResponseSchema>;
