import { generateKeyPairSync, randomUUID, sign } from "node:crypto";
import { vi } from "vitest";

const GOOGLE_CERTS_URL = "https://www.googleapis.com/oauth2/v3/certs";
/** The `googleClientId` of `bootstrapTestAuthApp`. */
const GOOGLE_CLIENT_ID = "test-google-client-id";

/**
 * Google ID tokens for specs: signed with a local key whose public half is
 * served in place of Google's certificates (the only faked `fetch`, every
 * other request goes through). `restore()` puts the real `fetch` back.
 */
export function fakeGoogleIdTokens(): {
  /** `picture`: the account photo URL Google puts in the token, Better Auth's `user.image`. */
  idToken(email: string, sub: string, claims?: { picture?: string }): string;
  restore(): void;
} {
  const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
  const kid = randomUUID();
  const realFetch = globalThis.fetch;
  const jwk = { ...publicKey.export({ format: "jwk" }), kid, alg: "RS256", use: "sig" };
  const fetchSpy = vi.spyOn(globalThis, "fetch").mockImplementation((input, init) => {
    const url = input instanceof Request ? input.url : String(input);
    return url === GOOGLE_CERTS_URL ? Promise.resolve(Response.json({ keys: [jwk] })) : realFetch(input, init);
  });

  return {
    idToken(email, sub, claims = {}) {
      const encode = (part: object) => Buffer.from(JSON.stringify(part)).toString("base64url");
      const now = Math.floor(Date.now() / 1000);
      const header = encode({ alg: "RS256", kid, typ: "JWT" });
      const payload = encode({
        iss: "https://accounts.google.com",
        aud: GOOGLE_CLIENT_ID,
        sub,
        email,
        email_verified: true,
        name: "Jeanne Martin",
        ...claims,
        iat: now,
        exp: now + 600,
      });
      const signature = sign("sha256", Buffer.from(`${header}.${payload}`), privateKey).toString("base64url");
      return `${header}.${payload}.${signature}`;
    },
    restore() {
      fetchSpy.mockRestore();
    },
  };
}
