import { Heading, Text } from "@react-email/components";
import { render } from "@react-email/render";
import { EmailButton, EmailLayout, PREVIEW_LOGO_URL } from "./email-layout.js";

export interface ResetPasswordEmailProps {
  url: string;
  /** Absolute URL of the header wordmark PNG (ADR-032 §2). */
  logoUrl: string;
}

/** Password reset email (ADR-023). */
export function ResetPasswordEmail({ url, logoUrl }: ResetPasswordEmailProps) {
  return (
    <EmailLayout preview="Reset your Nervo password" logoUrl={logoUrl}>
      <Heading as="h1">Nervo</Heading>
      <Text>We received a request to reset your password.</Text>
      <EmailButton href={url}>Reset password</EmailButton>
      <Text style={{ color: "#666666", fontSize: "12px" }}>
        If you didn't request this, you can ignore this email — your password won't change.
      </Text>
    </EmailLayout>
  );
}

ResetPasswordEmail.PreviewProps = {
  url: "https://api.strava.echimine.fr/api/auth/reset-password?token=preview",
  logoUrl: PREVIEW_LOGO_URL,
} satisfies ResetPasswordEmailProps;

export async function renderResetPasswordEmail(props: ResetPasswordEmailProps): Promise<string> {
  return render(<ResetPasswordEmail {...props} />);
}
