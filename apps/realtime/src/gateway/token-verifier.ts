import jwt from "jsonwebtoken";
import {
  REALTIME_TOKEN_ALGORITHM,
  REALTIME_TOKEN_AUDIENCE,
  REALTIME_TOKEN_ISSUER,
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
