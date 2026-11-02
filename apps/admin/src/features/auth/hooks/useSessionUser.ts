import { useQuery } from "@tanstack/react-query";
import { getSessionUser } from "../api";
import { authKeys } from "../query-keys";

/** The signed-in user as Better Auth sees it, with its `twoFactorEnabled` flag. */
export function useSessionUser() {
  return useQuery({
    queryKey: authKeys.session,
    queryFn: getSessionUser,
    retry: false,
  });
}
