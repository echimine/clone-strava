import { createAuthClient } from "better-auth/react";

/**
 * Better Auth client (ADR-012, ADR-013 §"Authentication and authorization").
 * No `baseURL`: requests go to `/api/auth/...` on the backoffice's own
 * origin, forwarded to the API by the Next.js proxy in `next.config.ts`
 * (same-origin cookie, no CORS).
 */
export const authClient = createAuthClient();

export const { signIn, signOut } = authClient;
