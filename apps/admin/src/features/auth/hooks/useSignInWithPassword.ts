import { useMutation } from "@tanstack/react-query";
import { hardNavigate } from "@/lib/navigation";
import { signInWithPassword } from "../api";

/**
 * First step of the sign-in. Without 2FA, the session is open at once and
 * the backoffice loads (its admin pages then require 2FA setup, ADR-022
 * §5); with 2FA, the caller moves on to the second factor.
 */
export function useSignInWithPassword() {
  return useMutation({
    mutationFn: signInWithPassword,
    onSuccess: (result) => {
      if (!result.twoFactorRequired) {
        hardNavigate("/");
      }
    },
  });
}
