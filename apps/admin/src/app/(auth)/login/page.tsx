import { LoginFlow, type LoginNotice } from "@/features/auth/components/LoginFlow";

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ reason?: string | string[] }>;
}) {
  const { reason } = await searchParams;
  // `apiClient` sends here with `?reason=strong-session` after closing a session
  // `/v1/admin/*` refused (ADR-035 §3).
  const notice: LoginNotice = reason === "strong-session" ? "strong-session" : null;

  return <LoginFlow notice={notice} />;
}
