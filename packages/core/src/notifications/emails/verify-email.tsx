import { Heading, Text } from "@react-email/components";
import { render } from "@react-email/render";
import { type BrandedEmailProps, EmailButton, EmailLayout, PREVIEW_LOGO_URL } from "./email-layout.js";

export interface VerifyEmailProps extends BrandedEmailProps {
  url: string;
}

/** Signup verification email (ADR-023). */
export function VerifyEmail({ url, logoUrl }: VerifyEmailProps) {
  return (
    <EmailLayout preview="Verify your Nervo account" logoUrl={logoUrl}>
      <Heading as="h1">Nervo</Heading>
      <Text>Confirm your email address to finish creating your account.</Text>
      <EmailButton href={url}>Verify email</EmailButton>
      <Text style={{ color: "#666666", fontSize: "12px" }}>
        If you didn't create this account, you can ignore this email.
      </Text>
    </EmailLayout>
  );
}

VerifyEmail.PreviewProps = {
  url: "https://api.strava.echimine.fr/api/auth/verify-email?token=preview",
  logoUrl: PREVIEW_LOGO_URL,
} satisfies VerifyEmailProps;

export async function renderVerifyEmail(props: VerifyEmailProps): Promise<string> {
  return render(<VerifyEmail {...props} />);
}
