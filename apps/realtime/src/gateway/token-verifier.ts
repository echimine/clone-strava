import jwt from "jsonwebtoken";
import {
  REALTIME_GRANT_AUDIENCE,
  REALTIME_TOKEN_ALGORITHM,
  REALTIME_TOKEN_AUDIENCE,
  REALTIME_TOKEN_ISSUER,
  realtimeGrantClaimsSchema,
  realtimeTokenClaimsSchema,
  type RealtimeTokenClaims,
} from "@repo/realtime";

/**
 * Verifies a realtime JWT locally: signature, algorithm, issuer, audience and
 * expiration (ADR-010 §3-4). No network call. Never throws: any failure
 * (malformed token, wrong signature, expired, wrong claims shape) returns
 * `null`, so the caller can uniformly respond `401`.
 */
export function verifyRealtimeToken(
  token: string,
  secret: string,
): RealtimeTokenClaims | null {
  try {
    const payload = jwt.verify(token, secret, {
      algorithms: [REALTIME_TOKEN_ALGORITHM],
      issuer: REALTIME_TOKEN_ISSUER,
      audience: REALTIME_TOKEN_AUDIENCE,
    });

    if (typeof payload !== "object" || payload === null) {
      return null;
    }

    const result = realtimeTokenClaimsSchema.safeParse(payload);
    if (!result.success) {
      return null;
    }

    return result.data;
  } catch {
    return null;
  }
}

/**
 * Verifies a subscription grant locally (ADR-034 §5): signature, algorithm,
 * issuer, grant audience and expiration, then that it was issued for exactly
 * `topic` and to the connection's user. Never throws.
 */
export function verifySubscriptionGrant(
  grant: string,
  secret: string,
  request: { topic: string; userId: string },
): boolean {
  try {
    const payload = jwt.verify(grant, secret, {
      algorithms: [REALTIME_TOKEN_ALGORITHM],
      issuer: REALTIME_TOKEN_ISSUER,
      audience: REALTIME_GRANT_AUDIENCE,
    });
    const result = realtimeGrantClaimsSchema.safeParse(payload);
    return result.success && result.data.topic === request.topic && result.data.sub === request.userId;
  } catch {
    return false;
  }
}

/** Extracts the bearer token from an `Authorization` header value, if present. */
export function extractBearerToken(authorization: string | undefined): string | null {
  if (!authorization) {
    return null;
  }
  const [scheme, token] = authorization.split(" ");
  if (scheme?.toLowerCase() !== "bearer" || !token) {
    return null;
  }
  return token;
}
