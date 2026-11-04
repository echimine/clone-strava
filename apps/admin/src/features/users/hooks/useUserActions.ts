import { useMutation, useQueryClient } from "@tanstack/react-query";
import type { BanDuration, UserRole } from "@repo/contracts";
import {
  banUser,
  deleteUser,
  resetProfile,
  setUserRole,
  signOutUser,
  unbanUser,
  type ProfileReset,
} from "@/features/users/api";
import { journalKey, userKeys } from "@/features/users/query-keys";

/**
 * The user sheet's actions (ADR-038 §5): the Sanctions on the account and the admin role. Each
 * refreshes the sheet, the lists and the Journal once done; the caller toasts and closes its
 * dialog.
 */
export function useUserActions(userId: string) {
  const queryClient = useQueryClient();
  const onSuccess = async () => {
    await Promise.all([
      queryClient.invalidateQueries({ queryKey: userKeys.all }),
      queryClient.invalidateQueries({ queryKey: journalKey }),
    ]);
  };

  return {
    ban: useMutation({
      mutationFn: ({ duration, reason }: { duration: BanDuration; reason: string }) => banUser(userId, duration, reason),
      onSuccess,
    }),
    unban: useMutation({ mutationFn: (reason: string) => unbanUser(userId, reason), onSuccess }),
    signOut: useMutation({ mutationFn: (reason: string) => signOutUser(userId, reason), onSuccess }),
    reset: useMutation({
      mutationFn: ({ reset, reason }: { reset: ProfileReset; reason: string }) => resetProfile(userId, reset, reason),
      onSuccess,
    }),
    // The account is gone: its sheet leaves the cache instead of being refetched (a 404).
    remove: useMutation({
      mutationFn: (reason: string) => deleteUser(userId, reason),
      onSuccess: async () => {
        queryClient.removeQueries({ queryKey: userKeys.detail(userId) });
        await Promise.all([
          queryClient.invalidateQueries({ queryKey: userKeys.lists() }),
          queryClient.invalidateQueries({ queryKey: journalKey }),
        ]);
      },
    }),
    setRole: useMutation({
      mutationFn: ({ role, reason }: { role: UserRole; reason: string }) => setUserRole(userId, role, reason),
      onSuccess,
    }),
  };
}
