import type { createAuthInstance } from "./create-auth-instance.js";

/**
 * Type of the value built by `createAuthInstance` (plugins included, e.g.
 * `admin()`'s `user.role`). Kept in its own file, separate from
 * `auth.constants.ts`, so that file and `create-auth-instance.ts` do not
 * import each other (`.dependency-cruiser.cjs` `no-circular`).
 */
export type AuthInstance = ReturnType<typeof createAuthInstance>;
