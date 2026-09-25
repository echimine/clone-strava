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

export interface VerifyEmailProps {
  url: string;
}

/** Signup verification email (ADR-023). */
export function VerifyEmail({ url }: VerifyEmailProps) {
  return (
    <Html lang="en">
      <Head />
      <Preview>Verify your Clone Strava account</Preview>
      <Body style={{ fontFamily: "sans-serif", backgroundColor: "#f6f6f6" }}>
        <Container style={{ backgroundColor: "#ffffff", padding: "32px", borderRadius: "8px" }}>
          <Heading as="h1">Clone Strava</Heading>
          <Text>Confirm your email address to finish creating your account.</Text>
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
            Verify email
          </Button>
          <Text style={{ color: "#666666", fontSize: "12px" }}>
            If you didn't create this account, you can ignore this email.
          </Text>
        </Container>
      </Body>
    </Html>
  );
}

VerifyEmail.PreviewProps = {
  url: "https://api.strava.echimine.fr/api/auth/verify-email?token=preview",
} satisfies VerifyEmailProps;

export async function renderVerifyEmail(props: VerifyEmailProps): Promise<string> {
  return render(<VerifyEmail {...props} />);
}
