import jwt from "jsonwebtoken";
import { describe, expect, it } from "vitest";
import {
  REALTIME_GRANT_AUDIENCE,
  REALTIME_TOKEN_ALGORITHM,
  REALTIME_TOKEN_AUDIENCE,
  REALTIME_TOKEN_ISSUER,
  activityTopic,
  userTopic,
} from "@repo/realtime";
import { extractBearerToken, verifyRealtimeToken, verifySubscriptionGrant } from "./token-verifier.js";

const SECRET = "test-secret-at-least-32-characters-long";
const USER_ID = "11111111-1111-4111-8111-111111111111";

function sign(overrides: Partial<jwt.SignOptions & { payload: Record<string, unknown> }> = {}) {
  const { payload, ...options } = overrides;
  return jwt.sign(
    { sub: USER_ID, topics: [userTopic(USER_ID)], ...payload },
    SECRET,
    {
      algorithm: REALTIME_TOKEN_ALGORITHM,
      issuer: REALTIME_TOKEN_ISSUER,
      audience: REALTIME_TOKEN_AUDIENCE,
      expiresIn: 60,
      ...options,
    },
  );
}

describe("verifyRealtimeToken", () => {
  it("accepts a well-formed token", () => {
    const claims = verifyRealtimeToken(sign(), SECRET);
    expect(claims).toEqual({ sub: USER_ID, topics: [userTopic(USER_ID)] });
  });

  it("rejects a token signed with the wrong secret", () => {
    expect(verifyRealtimeToken(sign(), "wrong-secret")).toBeNull();
  });

  it("rejects an expired token", () => {
    const token = sign({ expiresIn: -1 });
    expect(verifyRealtimeToken(token, SECRET)).toBeNull();
  });

  it("rejects a token with the wrong issuer", () => {
    const token = sign({ issuer: "someone-else" });
    expect(verifyRealtimeToken(token, SECRET)).toBeNull();
  });

  it("rejects a token with the wrong audience", () => {
    const token = sign({ audience: "someone-else" });
    expect(verifyRealtimeToken(token, SECRET)).toBeNull();
  });

  it("rejects a token missing the topics claim", () => {
    const token = jwt.sign({ sub: USER_ID }, SECRET, {
      algorithm: REALTIME_TOKEN_ALGORITHM,
      issuer: REALTIME_TOKEN_ISSUER,
      audience: REALTIME_TOKEN_AUDIENCE,
      expiresIn: 60,
    });
    expect(verifyRealtimeToken(token, SECRET)).toBeNull();
  });

  it("rejects garbage input without throwing", () => {
    expect(verifyRealtimeToken("not-a-jwt", SECRET)).toBeNull();
  });
});

describe("verifySubscriptionGrant", () => {
  const ACTIVITY_ID = "33333333-3333-4333-8333-333333333333";
  const TOPIC = activityTopic(ACTIVITY_ID);

  function grant(
    overrides: Partial<jwt.SignOptions & { payload: Record<string, unknown> }> = {},
  ) {
    const { payload, ...options } = overrides;
    return jwt.sign({ sub: USER_ID, topic: TOPIC, ...payload }, SECRET, {
      algorithm: REALTIME_TOKEN_ALGORITHM,
      issuer: REALTIME_TOKEN_ISSUER,
      audience: REALTIME_GRANT_AUDIENCE,
      expiresIn: 60,
      ...options,
    });
  }

  const request = { topic: TOPIC, userId: USER_ID };

  it("accepts a valid grant for the requested topic and the connection's user", () => {
    expect(verifySubscriptionGrant(grant(), SECRET, request)).toBe(true);
  });

  it("rejects an expired grant", () => {
    expect(verifySubscriptionGrant(grant({ expiresIn: -1 }), SECRET, request)).toBe(false);
  });

  it("rejects a connection token used as a grant (wrong audience)", () => {
    const connectionToken = sign({ payload: { topics: [TOPIC] } });
    expect(verifySubscriptionGrant(connectionToken, SECRET, request)).toBe(false);
    expect(verifySubscriptionGrant(grant({ audience: "someone-else" }), SECRET, request)).toBe(false);
  });

  it("rejects a grant issued to another user", () => {
    const other = "44444444-4444-4444-8444-444444444444";
    expect(verifySubscriptionGrant(grant(), SECRET, { topic: TOPIC, userId: other })).toBe(false);
  });

  it("rejects a grant for another topic", () => {
    const otherTopic = activityTopic("55555555-5555-4555-8555-555555555555");
    expect(verifySubscriptionGrant(grant(), SECRET, { topic: otherTopic, userId: USER_ID })).toBe(false);
  });

  it("rejects a grant signed with another secret, issuer or algorithm", () => {
    expect(verifySubscriptionGrant(grant(), "wrong-secret", request)).toBe(false);
    expect(verifySubscriptionGrant(grant({ issuer: "someone-else" }), SECRET, request)).toBe(false);
    expect(verifySubscriptionGrant(grant({ algorithm: "HS512" }), SECRET, request)).toBe(false);
  });

  it("rejects garbage without throwing", () => {
    expect(verifySubscriptionGrant("not-a-jwt", SECRET, request)).toBe(false);
  });
});

describe("verifyRealtimeToken against a grant", () => {
  it("never accepts a grant as a connection token", () => {
    const grant = jwt.sign({ sub: USER_ID, topic: "activity:x", topics: [userTopic(USER_ID)] }, SECRET, {
      algorithm: REALTIME_TOKEN_ALGORITHM,
      issuer: REALTIME_TOKEN_ISSUER,
      audience: REALTIME_GRANT_AUDIENCE,
      expiresIn: 60,
    });
    expect(verifyRealtimeToken(grant, SECRET)).toBeNull();
  });
});

describe("extractBearerToken", () => {
  it("extracts the token from a Bearer authorization header", () => {
    expect(extractBearerToken("Bearer abc.def.ghi")).toBe("abc.def.ghi");
  });

  it("returns null when the header is missing", () => {
    expect(extractBearerToken(undefined)).toBeNull();
  });

  it("returns null for a non-Bearer scheme", () => {
    expect(extractBearerToken("Basic abc")).toBeNull();
  });
});
