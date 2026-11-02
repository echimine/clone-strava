import { useMutation } from "@tanstack/react-query";
import { startTwoFactorSetup, verifyEmailCode, verifyTotpCode } from "../api";

/** How the admin chooses to receive the second factor (ADR-022 §5). */
export type SetupMethod = "totp" | "otp";

/** Checks the password and creates the TOTP secret and the backup codes. */
export function useStartTwoFactorSetup() {
  return useMutation({ mutationFn: startTwoFactorSetup });
}

/**
 * The first valid code turns 2FA on. Better Auth then replaces the session
 * with one opened by `/two-factor/verify-*`, i.e. `password_2fa`
 * (ADR-035 §3): the admin pages open without signing in again.
 */
export function useConfirmTwoFactorSetup() {
  return useMutation({
    mutationFn: ({ method, code }: { method: SetupMethod; code: string }) =>
      method === "totp" ? verifyTotpCode(code) : verifyEmailCode(code),
  });
}
