import { adminAccessResponseSchema, type AdminAccessResponse } from "@repo/contracts";
import { apiClient } from "@/lib/apiClient";
import { authClient } from "@/lib/auth-client";
import { AuthRequestError } from "./lib/auth-request-error";

/**
 * `GET /v1/admin`: whether `AdminGuard` lets this session through. Its
 * refusals (`ADMIN_2FA_REQUIRED`, `ADMIN_STRONG_SESSION_REQUIRED`) are
 * acted on by `apiClient`, like on every other admin route.
 */
export function getAdminAccess(signal?: AbortSignal): Promise<AdminAccessResponse> {
  return apiClient("/v1/admin", adminAccessResponseSchema, { signal });
}

/**
 * Better Auth calls of the sign-in and 2FA screens (ADR-013 rule 4, ADR-022
 * §5). Each one throws `AuthRequestError` instead of returning `{ error }`,
 * so the hooks can use TanStack Query mutations like the rest of the app.
 *
 * `trustDevice` is never sent: a trusted device skips the second factor at
 * the next sign-in, and that session would not be `password_2fa`
 * (ADR-035 §3), so `/v1/admin/*` would refuse it.
 */

/** The second factors `signIn.email` offers once the password is right. */
export type TwoFactorMethod = "totp" | "otp";

type AuthResult<Data> = {
  data: Data | null;
  error: { code?: string; message?: string; status: number } | null;
};

function unwrap<Data>({ data, error }: AuthResult<Data>): Data {
  if (error) {
    throw new AuthRequestError(error.status, error.code, error.message);
  }
  return data as Data;
}

export type PasswordSignInResult =
  | { twoFactorRequired: false }
  | { twoFactorRequired: true; methods: TwoFactorMethod[] };

/** `POST /sign-in/email`: the session is only opened after the second factor when 2FA is on. */
export async function signInWithPassword(credentials: {
  email: string;
  password: string;
}): Promise<PasswordSignInResult> {
  const data = unwrap(await authClient.signIn.email(credentials));
  if (data && "twoFactorRedirect" in data && data.twoFactorRedirect) {
    const methods = (data as { twoFactorMethods?: TwoFactorMethod[] }).twoFactorMethods ?? [];
    return { twoFactorRequired: true, methods };
  }
  return { twoFactorRequired: false };
}

export type SessionUser = { email: string; twoFactorEnabled: boolean };

/** `GET /get-session`: the signed-in user, `null` without a session. */
export async function getSessionUser(): Promise<SessionUser | null> {
  const data = unwrap(await authClient.getSession());
  if (!data) {
    return null;
  }
  return { email: data.user.email, twoFactorEnabled: data.user.twoFactorEnabled === true };
}

/** `POST /two-factor/verify-totp`: the authenticator app code. */
export async function verifyTotpCode(code: string): Promise<void> {
  unwrap(await authClient.twoFactor.verifyTotp({ code }));
}

/** `POST /two-factor/send-otp`: mails a 2FA code to the admin. */
export async function sendEmailCode(): Promise<void> {
  unwrap(await authClient.twoFactor.sendOtp());
}

/** `POST /two-factor/verify-otp`: the code received by email. */
export async function verifyEmailCode(code: string): Promise<void> {
  unwrap(await authClient.twoFactor.verifyOtp({ code }));
}

/** `POST /two-factor/verify-backup-code`: one of the backup codes, used once. */
export async function verifyBackupCode(code: string): Promise<void> {
  unwrap(await authClient.twoFactor.verifyBackupCode({ code }));
}

export type TwoFactorEnrollment = { totpURI: string; backupCodes: string[] };

/**
 * `POST /two-factor/enable`: creates the TOTP secret and the backup codes.
 * 2FA is only turned on by the first verified code, TOTP or email.
 */
export async function startTwoFactorSetup(password: string): Promise<TwoFactorEnrollment> {
  const data = unwrap(await authClient.twoFactor.enable({ password }));
  if (!("totpURI" in data) || !data.totpURI || !data.backupCodes) {
    throw new AuthRequestError(500, "TOTP_NOT_CONFIGURED", "TOTP is not available");
  }
  return { totpURI: data.totpURI, backupCodes: data.backupCodes };
}
