import { Text } from "@react-email/components";
import type { EmailTemplateData } from "@repo/contracts";
import { render } from "@react-email/render";
import { PREVIEW_LOGO_URL } from "./email-layout.js";
import { AthleteEmailFrame, type AthleteEmailProps } from "./athlete-email-parts.js";

export type AccountDeletedEmailProps = AthleteEmailProps & EmailTemplateData<"account-deleted">;

export const ACCOUNT_DELETED_SUBJECT = "Votre compte Nervo a été supprimé";

/**
 * « Votre compte Nervo a été supprimé » (ADR-038 §13), by the athlete or by an Administrator; the
 * reason and the contact address only for a Sanction (`reason` set).
 */
export function AccountDeletedEmail({ reason, ...props }: AccountDeletedEmailProps) {
  const bySanction = reason !== null;
  return (
    <AthleteEmailFrame
      {...props}
      reason={reason}
      preview={ACCOUNT_DELETED_SUBJECT}
      heading="Compte supprimé"
      withContact={bySanction}
    >
      <Text>
        {bySanction
          ? "Votre compte Nervo et ses données ont été supprimés par l'équipe Nervo."
          : "Votre compte Nervo et ses données ont été supprimés, comme vous l'avez demandé."}
      </Text>
      <Text>
        Votre profil, vos Activités, leurs photos et vidéos et vos commentaires ont été effacés. Cette suppression est
        définitive.
      </Text>
    </AthleteEmailFrame>
  );
}

AccountDeletedEmail.PreviewProps = {
  firstName: "Léa",
  reason: null,
  contactEmail: "contact@strava.echimine.fr",
  logoUrl: PREVIEW_LOGO_URL,
} satisfies AccountDeletedEmailProps;

export function renderAccountDeletedEmail(props: AccountDeletedEmailProps): Promise<string> {
  return render(<AccountDeletedEmail {...props} />);
}
