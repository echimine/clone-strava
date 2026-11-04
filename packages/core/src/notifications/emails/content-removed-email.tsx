import { Text } from "@react-email/components";
import type { EmailTemplateData, RemovedContent } from "@repo/contracts";
import { render } from "@react-email/render";
import { PREVIEW_LOGO_URL } from "./email-layout.js";
import {
  AthleteEmailFrame,
  type AthleteEmailProps,
  activityLabel,
  parisDay,
  truncatedQuote,
} from "./athlete-email-parts.js";

export type ContentRemovedEmailProps = AthleteEmailProps & EmailTemplateData<"content-removed">;

export const CONTENT_REMOVED_SUBJECT = "Un contenu de votre compte Nervo a été retiré";

/** What was removed, named without a link (ADR-038 §4). */
function removalSentence(content: RemovedContent): string {
  switch (content.kind) {
    case "activity":
      return `L'équipe Nervo vous informe que votre ${activityLabel(content.activity)} a été retirée.`;
    case "media":
      return `L'équipe Nervo vous informe qu'une photo ou une vidéo de votre ${activityLabel(content.activity)} a été retirée.`;
    case "activity-text":
      return `L'équipe Nervo vous informe que le titre et la description de votre ${activityLabel(content.activity)} ont été réinitialisés.`;
    case "comment": {
      const day = content.postedAt ? ` du ${parisDay(content.postedAt)}` : "";
      const where = content.activity ? ` sur l'Activité « ${content.activity.title} »` : "";
      return `L'équipe Nervo vous informe que votre commentaire${day}${where} a été retiré :`;
    }
  }
}

/** A comment, an Activity, a Media, or an Activity's text removed (ADR-038 §4). */
export function ContentRemovedEmail({ content, ...props }: ContentRemovedEmailProps) {
  return (
    <AthleteEmailFrame {...props} preview={CONTENT_REMOVED_SUBJECT} heading="Contenu retiré" withContact>
      <Text>{removalSentence(content)}</Text>
      {content.kind === "comment" && (
        <Text style={{ borderLeft: "3px solid #dddddd", paddingLeft: "12px", color: "#444444" }}>
          {`« ${truncatedQuote(content.body)} »`}
        </Text>
      )}
    </AthleteEmailFrame>
  );
}

ContentRemovedEmail.PreviewProps = {
  firstName: "Léa",
  reason: "Propos injurieux",
  content: {
    kind: "comment",
    body: "Quelle allure de tortue, tu devrais arrêter le vélo",
    postedAt: "2026-11-03T21:00:00.000Z",
    activity: { title: "Sortie du dimanche", startedAt: "2026-11-02T08:30:00.000Z" },
  },
  contactEmail: "contact@strava.echimine.fr",
  logoUrl: PREVIEW_LOGO_URL,
} satisfies ContentRemovedEmailProps;

export function renderContentRemovedEmail(props: ContentRemovedEmailProps): Promise<string> {
  return render(<ContentRemovedEmail {...props} />);
}
