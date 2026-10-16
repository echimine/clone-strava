import {
  Body,
  Container,
  Head,
  Heading,
  Html,
  Preview,
  Text,
} from "@react-email/components";
import { render } from "@react-email/render";

export interface AdminOtpEmailProps {
  otp: string;
  email: string;
}

/** Masks all but the first character of the local part, e.g. `jdoe@example.com` -> `j***@example.com` (ADR-023 §2). */
function maskEmail(email: string): string {
  const [local, domain] = email.split("@");
  if (!local || !domain) {
    return email;
  }
  return `${local[0]}***@${domain}`;
}

/** Admin 2FA one-time code email (ADR-022 §5, ADR-023 §2). */
export function AdminOtpEmail({ otp, email }: AdminOtpEmailProps) {
  return (
    <Html lang="en">
      <Head />
      <Preview>Your Nervo admin verification code</Preview>
      <Body style={{ fontFamily: "sans-serif", backgroundColor: "#f6f6f6" }}>
        <Container style={{ backgroundColor: "#ffffff", padding: "32px", borderRadius: "8px" }}>
          <Heading as="h1">Nervo admin</Heading>
          <Text>Verification code for {maskEmail(email)}:</Text>
          <Text style={{ fontSize: "28px", fontWeight: "bold", letterSpacing: "4px" }}>{otp}</Text>
          <Text style={{ color: "#666666", fontSize: "12px" }}>
            This code expires shortly. If you didn't request it, secure your account.
          </Text>
        </Container>
      </Body>
    </Html>
  );
}

AdminOtpEmail.PreviewProps = {
  otp: "123456",
  email: "admin@example.com",
} satisfies AdminOtpEmailProps;

export async function renderAdminOtpEmail(props: AdminOtpEmailProps): Promise<string> {
  return render(<AdminOtpEmail {...props} />);
}
