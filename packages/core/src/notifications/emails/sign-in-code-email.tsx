import { Heading, Text } from "@react-email/components";
import { render } from "@react-email/render";
import {
  type BrandedEmailProps,
  EmailLayout,
  PREVIEW_LOGO_URL,
} from "./email-layout.js";

export interface SignInCodeEmailProps extends BrandedEmailProps {
  otp: string;
}

/**
 * Sign-in code email of the iOS app (ADR-035 §2, ADR-023): same frame as
 * the admin OTP email, in French since it reaches the app's users. The
 * validity matches the `emailOTP` plugin's default `expiresIn` (300 s).
 */
export function SignInCodeEmail({ otp, logoUrl }: SignInCodeEmailProps) {
  return (
    <EmailLayout
      preview={`Votre code de connexion Nervo : ${otp}`}
      logoUrl={logoUrl}
      lang="fr"
    >
      <Heading as="h1">Votre code de connexion</Heading>
      <Text>Saisissez ce code dans l'app Nervo pour vous connecter :</Text>
      <Text
        style={{ fontSize: "28px", fontWeight: "bold", letterSpacing: "4px" }}
      >
        {otp}
      </Text>
      <Text style={{ color: "#666666", fontSize: "12px" }}>
        Ce code est valable 5 minutes. Si vous ne l'avez pas demandé, ignorez
        cet email.
      </Text>
    </EmailLayout>
  );
}

SignInCodeEmail.PreviewProps = {
  otp: "123456",
  logoUrl: PREVIEW_LOGO_URL,
} satisfies SignInCodeEmailProps;

export async function renderSignInCodeEmail(
  props: SignInCodeEmailProps,
): Promise<string> {
  return render(<SignInCodeEmail {...props} />);
}
