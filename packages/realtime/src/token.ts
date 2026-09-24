import { z } from "zod";

/**
 * Shared constants and claim schema for the short-lived realtime JWT
 * (ADR-010 §3). No `jsonwebtoken` dependency here: signing and local
 * verification live in `apps/api` and `apps/realtime` respectively, this
 * package only fixes the shared contract between them.
 */

export const REALTIME_TOKEN_ISSUER = "clone-strava-api";
export const REALTIME_TOKEN_AUDIENCE = "clone-strava-realtime";

/** Token lifetime, in seconds. */
export const REALTIME_TOKEN_TTL_SECONDS = 60;

export const REALTIME_TOKEN_ALGORITHM = "HS256";

/** Claims carried by the realtime JWT, beyond the standard `iss`/`aud`/`exp`. */
export const realtimeTokenClaimsSchema = z.object({
  sub: z.string(),
  topics: z.array(z.string()),
});
export type RealtimeTokenClaims = z.infer<typeof realtimeTokenClaimsSchema>;
