import { Resend } from "resend";

/** Thin factory so `NotificationsService` never calls `new Resend(...)` directly. */
export function createResendClient(apiKey: string): Resend {
  return new Resend(apiKey);
}
