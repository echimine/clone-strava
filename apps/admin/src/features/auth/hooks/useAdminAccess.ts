import { useQuery } from "@tanstack/react-query";
import { getAdminAccess } from "../api";
import { authKeys } from "../query-keys";

/**
 * Asks `/v1/admin` up front whether the session may use the admin routes,
 * so the `(admin)` layout sends an admin without 2FA to its setup, or a
 * weak session back to the sign-in (ADR-022 §5, ADR-035 §3), before any
 * page shows. Only enabled for an admin: a plain user sees "Accès refusé".
 */
export function useAdminAccess(enabled: boolean) {
  return useQuery({
    queryKey: authKeys.adminAccess,
    queryFn: ({ signal }) => getAdminAccess(signal),
    enabled,
    retry: false,
  });
}
