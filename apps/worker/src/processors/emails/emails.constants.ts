export interface EmailsProcessorOptions {
  /** `RESEND_API_KEY`; without it every `send-email` job fails (and stays retryable from the Jobs screen). */
  resendApiKey?: string;
  /** `CONTACT_EMAIL`: Reply-To and the address the e-mails give (ADR-038 §4). */
  contactEmail?: string;
  /** The backoffice origin, host of the e-mails' wordmark (ADR-032 §2). */
  adminOrigin: string;
}

export const EMAILS_PROCESSOR_OPTIONS = Symbol("EMAILS_PROCESSOR_OPTIONS");
