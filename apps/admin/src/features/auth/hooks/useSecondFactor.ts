import { useMutation } from "@tanstack/react-query";
import { hardNavigate } from "@/lib/navigation";
import { sendEmailCode, verifyBackupCode, verifyEmailCode, verifyTotpCode } from "../api";

/** Second factor kinds the admin can type a code for (ADR-022 §5). */
export type SecondFactorKind = "totp" | "otp" | "backup";

const verifiers: Record<SecondFactorKind, (code: string) => Promise<void>> = {
  totp: verifyTotpCode,
  otp: verifyEmailCode,
  backup: verifyBackupCode,
};

/**
 * Verifies the second factor of a sign-in. Better Auth then opens the
 * `password_2fa` session (ADR-035 §3); the full reload starts the
 * backoffice with an empty cache.
 */
export function useVerifySecondFactor() {
  return useMutation({
    mutationFn: ({ kind, code }: { kind: SecondFactorKind; code: string }) => verifiers[kind](code),
    onSuccess: () => hardNavigate("/"),
  });
}

/** Mails a 2FA code, at sign-in or while setting 2FA up by email. */
export function useSendEmailCode() {
  return useMutation({ mutationFn: sendEmailCode });
}
