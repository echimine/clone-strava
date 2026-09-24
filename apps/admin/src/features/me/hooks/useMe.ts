import { useQuery } from "@tanstack/react-query";
import { getMe } from "@/features/me/api";
import { meKeys } from "@/features/me/query-keys";

/**
 * Current administrator (ADR-013 §"Authentication and authorization" step
 * 2): used by the `(admin)` layout to check the session and the role.
 */
export function useMe() {
  return useQuery({
    queryKey: meKeys.all,
    queryFn: ({ signal }) => getMe(signal),
    retry: false,
  });
}
