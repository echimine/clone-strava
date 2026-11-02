import { twoFactorClient } from "better-auth/client/plugins";
import { createAuthClient } from "better-auth/react";

/**
 * Better Auth client (ADR-012, ADR-013 §"Authentication and authorization").
 * No `baseURL`: requests go to `/api/auth/...` on the backoffice's own
 * origin, forwarded to the API by the Next.js proxy in `next.config.ts`
 * (same-origin cookie, no CORS).
 *
 * `twoFactorClient` (ADR-022 §5): the second factor is asked for on the
 * sign-in page itself (`signIn.email` answers `twoFactorRedirect`), so no
 * `twoFactorPage` redirect is configured.
 */
export const authClient = createAuthClient({
  plugins: [twoFactorClient()],
  fetchOptions: {
    // Looks `fetch` up at call time instead of keeping the one present at
    // import, so the tests' MSW server (installed later) sees these calls.
    customFetchImpl: (input, init) => fetch(input, init),
  },
});

export const { signIn, signOut } = authClient;
