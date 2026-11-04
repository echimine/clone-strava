import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import type { PromotionalPremiumDuration } from "@repo/contracts";
import { getPremium, grantPremium, revokePremium, syncPremium } from "@/features/premium/api";
import { journalKey, premiumKeys, usersKey } from "@/features/premium/query-keys";

/** The athlete's Premium: state, detail, history, link to RevenueCat. */
export function usePremium(userId: string) {
  return useQuery({ queryKey: premiumKeys.user(userId), queryFn: ({ signal }) => getPremium(userId, signal) });
}

/**
 * The Premium actions (ADR-038 §12). Each refreshes the section, the user sheet and lists, and
 * the Journal once done; the caller toasts.
 */
export function usePremiumActions(userId: string) {
  const queryClient = useQueryClient();
  const onSuccess = async () => {
    await Promise.all([
      queryClient.invalidateQueries({ queryKey: premiumKeys.user(userId) }),
      queryClient.invalidateQueries({ queryKey: usersKey }),
      queryClient.invalidateQueries({ queryKey: journalKey }),
    ]);
  };

  return {
    sync: useMutation({ mutationFn: () => syncPremium(userId), onSuccess }),
    grant: useMutation({
      mutationFn: ({ duration, reason }: { duration: PromotionalPremiumDuration; reason: string }) =>
        grantPremium(userId, duration, reason),
      onSuccess,
    }),
    revoke: useMutation({ mutationFn: (reason: string) => revokePremium(userId, reason), onSuccess }),
  };
}
