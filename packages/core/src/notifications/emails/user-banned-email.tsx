import { Text } from "@react-email/components";
import type { EmailTemplateData } from "@repo/contracts";
import { render } from "@react-email/render";
import { PREVIEW_LOGO_URL } from "./email-layout.js";
import { AthleteEmailFrame, type AthleteEmailProps, parisDateTime } from "./athlete-email-parts.js";

export type UserBannedEmailProps = AthleteEmailProps & EmailTemplateData<"user-banned">;

export const USER_BANNED_SUBJECT = "Votre compte Nervo est suspendu";

/** Ban (ADR-038 §4, §6): until when, or « définitivement », and why. */
export function UserBannedEmail({ until, ...props }: UserBannedEmailProps) {
  const duration = until ? `jusqu'au ${parisDateTime(until)} (heure de Paris)` : "définitivement";
  return (
    <AthleteEmailFrame {...props} preview={USER_BANNED_SUBJECT} heading="Compte suspendu" withContact>
      <Text>{`Votre compte Nervo est suspendu ${duration}. Pendant la suspension, vous ne pouvez plus vous connecter à l'app et votre profil n'est plus visible des autres athlètes.`}</Text>
    </AthleteEmailFrame>
  );
}

UserBannedEmail.PreviewProps = {
  firstName: "Léa",
  reason: "Propos injurieux dans les commentaires",
  until: "2026-11-11T13:30:00.000Z",
  contactEmail: "contact@strava.echimine.fr",
  logoUrl: PREVIEW_LOGO_URL,
} satisfies UserBannedEmailProps;

export function renderUserBannedEmail(props: UserBannedEmailProps): Promise<string> {
  return render(<UserBannedEmail {...props} />);
}
