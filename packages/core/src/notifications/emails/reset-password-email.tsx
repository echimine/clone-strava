import {
  Body,
  Button,
  Container,
  Head,
  Heading,
  Html,
  Preview,
  Text,
} from "@react-email/components";
import { render } from "@react-email/render";

export interface ResetPasswordEmailProps {
  url: string;
}

/** Password reset email (ADR-023). */
export function ResetPasswordEmail({ url }: ResetPasswordEmailProps) {
  return (
    <Html lang="en">
      <Head />
      <Preview>Reset your Nervo password</Preview>
      <Body style={{ fontFamily: "sans-serif", backgroundColor: "#f6f6f6" }}>
        <Container style={{ backgroundColor: "#ffffff", padding: "32px", borderRadius: "8px" }}>
          <Heading as="h1">Nervo</Heading>
          <Text>We received a request to reset your password.</Text>
          <Button
            href={url}
            style={{
              backgroundColor: "#fc4c02",
              color: "#ffffff",
              padding: "12px 20px",
              borderRadius: "4px",
              textDecoration: "none",
              boxSizing: "border-box",
            }}
          >
            Reset password
          </Button>
          <Text style={{ color: "#666666", fontSize: "12px" }}>
            If you didn't request this, you can ignore this email — your password won't change.
          </Text>
        </Container>
      </Body>
    </Html>
  );
}

ResetPasswordEmail.PreviewProps = {
  url: "https://api.strava.echimine.fr/api/auth/reset-password?token=preview",
} satisfies ResetPasswordEmailProps;

export async function renderResetPasswordEmail(props: ResetPasswordEmailProps): Promise<string> {
  return render(<ResetPasswordEmail {...props} />);
}
