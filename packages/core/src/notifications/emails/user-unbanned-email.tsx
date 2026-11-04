import { Text } from "@react-email/components";
import type { EmailTemplateData } from "@repo/contracts";
import { render } from "@react-email/render";
import { PREVIEW_LOGO_URL } from "./email-layout.js";
import { AthleteEmailFrame, type AthleteEmailProps } from "./athlete-email-parts.js";

export type UserUnbannedEmailProps = AthleteEmailProps & EmailTemplateData<"user-unbanned">;

export const USER_UNBANNED_SUBJECT = "La suspension de votre compte Nervo est levée";

/** Ban lifted by an Administrator (ADR-038 §4); never sent when a temporary Ban ends by itself. */
export function UserUnbannedEmail(props: UserUnbannedEmailProps) {
  return (
    <AthleteEmailFrame {...props} preview={USER_UNBANNED_SUBJECT} heading="Suspension levée" withContact>
      <Text>
        La suspension de votre compte Nervo est levée. Vous pouvez de nouveau vous connecter à l'app, et votre
        profil est de nouveau visible des autres athlètes.
      </Text>
    </AthleteEmailFrame>
  );
}

UserUnbannedEmail.PreviewProps = {
  firstName: "Léa",
  reason: "Suspension levée après échange par e-mail",
  contactEmail: "contact@strava.echimine.fr",
  logoUrl: PREVIEW_LOGO_URL,
} satisfies UserUnbannedEmailProps;

export function renderUserUnbannedEmail(props: UserUnbannedEmailProps): Promise<string> {
  return render(<UserUnbannedEmail {...props} />);
}
