/** A refused Better Auth call (`/api/auth/*`), with Better Auth's own error code. */
export class AuthRequestError extends Error {
  readonly status: number;
  readonly code: string | undefined;

  constructor(status: number, code: string | undefined, message: string | undefined) {
    super(message ?? "Authentication request failed");
    this.name = "AuthRequestError";
    this.status = status;
    this.code = code;
  }
}

/** The 2FA challenge of this sign-in is gone: the password has to be entered again. */
const EXPIRED_SIGN_IN_CODES = new Set(["INVALID_TWO_FACTOR_COOKIE"]);

const MESSAGES: Record<string, string> = {
  INVALID_CODE: "Code incorrect.",
  INVALID_BACKUP_CODE: "Code de secours incorrect ou déjà utilisé.",
  OTP_HAS_EXPIRED: "Ce code a expiré. Demandez-en un nouveau.",
  TOO_MANY_ATTEMPTS_REQUEST_NEW_CODE: "Trop d'essais. Demandez un nouveau code.",
  ACCOUNT_TEMPORARILY_LOCKED:
    "Trop d'essais incorrects : le compte est bloqué pendant quelques minutes.",
  INVALID_TWO_FACTOR_COOKIE: "Votre connexion a expiré. Saisissez à nouveau votre mot de passe.",
  INVALID_PASSWORD: "Mot de passe incorrect.",
  INVALID_EMAIL_OR_PASSWORD: "E-mail ou mot de passe incorrect.",
};

/** Whether the sign-in has to restart from the password step. */
export function isExpiredSignIn(error: unknown): boolean {
  return error instanceof AuthRequestError && EXPIRED_SIGN_IN_CODES.has(error.code ?? "");
}

/** Message shown to the admin for a refused auth call. */
export function authErrorMessage(error: unknown): string {
  if (error instanceof AuthRequestError) {
    if (error.status === 429) {
      return "Trop de tentatives. Patientez quelques secondes puis réessayez.";
    }
    const message = error.code ? MESSAGES[error.code] : undefined;
    if (message) {
      return message;
    }
  }
  return "Une erreur est survenue. Réessayez.";
}
