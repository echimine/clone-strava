import { keepPreviousData, useQuery } from "@tanstack/react-query";
import {
  getUser,
  getUserReports,
  getUserSessions,
  listUsers,
  type UserListFilters,
} from "@/features/users/api";
import { userKeys } from "@/features/users/query-keys";

/** A page of the users list, server-side filtered, sorted and paged (ADR-038 §2, §5). */
export function useUsers(filters: UserListFilters) {
  return useQuery({
    queryKey: userKeys.list(filters),
    queryFn: ({ signal }) => listUsers(filters, signal),
    placeholderData: keepPreviousData,
  });
}

/** The user sheet's account, profile, Activity and Follows. */
export function useUser(id: string) {
  return useQuery({ queryKey: userKeys.detail(id), queryFn: ({ signal }) => getUser(id, signal) });
}

/** The account's open sessions. */
export function useUserSessions(id: string) {
  return useQuery({ queryKey: userKeys.sessions(id), queryFn: ({ signal }) => getUserSessions(id, signal) });
}

/** Reports received and sent. */
export function useUserReports(id: string) {
  return useQuery({ queryKey: userKeys.reports(id), queryFn: ({ signal }) => getUserReports(id, signal) });
}
