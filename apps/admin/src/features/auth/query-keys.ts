/** TanStack Query keys of the auth feature (ADR-013). */
export const authKeys = {
  all: ["auth"] as const,
  session: ["auth", "session"] as const,
  adminAccess: ["auth", "admin-access"] as const,
};
