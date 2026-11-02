import { TwoFactorSetup } from "@/features/auth/components/TwoFactorSetup";

/**
 * Outside the `(admin)` layout on purpose: that layout sends an admin
 * without 2FA here (`ADMIN_2FA_REQUIRED`, ADR-022 §5). The proxy still
 * requires a session cookie.
 */
export default function TwoFactorSetupPage() {
  return <TwoFactorSetup />;
}
