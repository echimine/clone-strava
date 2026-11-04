import { Text } from "@react-email/components";
import type { EmailTemplateData } from "@repo/contracts";
import { render } from "@react-email/render";
import { PREVIEW_LOGO_URL } from "./email-layout.js";
import { AthleteEmailFrame, type AthleteEmailProps } from "./athlete-email-parts.js";

export type ProfileResetEmailProps = AthleteEmailProps & EmailTemplateData<"profile-reset">;

export const PROFILE_RESET_SUBJECT = "Votre profil Nervo a été modifié";

const FIELD_SENTENCES: Record<ProfileResetEmailProps["field"], string> = {
  name: "votre nom a été remplacé par « Athlète »",
  bio: "votre bio a été effacée",
  avatar: "votre photo de profil a été retirée",
};

/** Name, bio or Avatar reset to its default (ADR-038 §4). */
export function ProfileResetEmail({ field, ...props }: ProfileResetEmailProps) {
  return (
    <AthleteEmailFrame {...props} preview={PROFILE_RESET_SUBJECT} heading="Profil modifié" withContact>
      <Text>{`L'équipe Nervo vous informe que ${FIELD_SENTENCES[field]}. Vous pouvez le modifier de nouveau depuis « Modifier le profil », dans le respect des règles de la communauté.`}</Text>
    </AthleteEmailFrame>
  );
}

ProfileResetEmail.PreviewProps = {
  firstName: "Léa",
  reason: "Nom à caractère publicitaire",
  field: "name",
  contactEmail: "contact@strava.echimine.fr",
  logoUrl: PREVIEW_LOGO_URL,
} satisfies ProfileResetEmailProps;

export function renderProfileResetEmail(props: ProfileResetEmailProps): Promise<string> {
  return render(<ProfileResetEmail {...props} />);
}
