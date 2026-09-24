import jwt from "jsonwebtoken";
import { describe, expect, it } from "vitest";
import {
  REALTIME_TOKEN_ALGORITHM,
  REALTIME_TOKEN_AUDIENCE,
  REALTIME_TOKEN_ISSUER,
  userTopic,
} from "@repo/realtime";
import { extractBearerToken, verifyRealtimeToken } from "./token-verifier.js";

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
