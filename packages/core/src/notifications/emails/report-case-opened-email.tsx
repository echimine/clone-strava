import { Heading, Text } from "@react-email/components";
import type { EmailTemplateData, ReportReason, ReportTargetType } from "@repo/contracts";
import { render } from "@react-email/render";
import { EmailButton, EmailLayout, PREVIEW_LOGO_URL, type BrandedEmailProps } from "./email-layout.js";

export type ReportCaseOpenedEmailProps = BrandedEmailProps & EmailTemplateData<"report-case-opened">;

export const REPORT_CASE_OPENED_SUBJECT = "Nouveau signalement à traiter";

const TARGETS: Record<ReportTargetType, string> = {
  comment: "un commentaire",
  activity: "une Activité",
  athlete: "un athlète",
  segment: "un Segment",
};

/** The app's reason labels (ADR-038 §9). */
const REASONS: Record<ReportReason, string> = {
  spam: "Spam ou publicité",
  harassment: "Harcèlement ou propos haineux",
  sexual_or_violent: "Contenu sexuel ou violent",
  impersonation: "Usurpation d'identité",
  other: "Autre",
};

/**
 * To every Administrator when a Report opens a case (ADR-038 §10), never on later Reports: what
 * kind of target, the reason, and the link to the case. Never a copy of the reported content.
 */
export function ReportCaseOpenedEmail({ targetType, reason, caseUrl, logoUrl }: ReportCaseOpenedEmailProps) {
  return (
    <EmailLayout preview={REPORT_CASE_OPENED_SUBJECT} logoUrl={logoUrl} lang="fr">
      <Heading as="h1" style={{ fontSize: "22px" }}>
        Nouveau signalement
      </Heading>
      <Text>
        Un athlète a signalé {TARGETS[targetType]} pour le motif « {REASONS[reason]} ». Un dossier est ouvert dans la
        file de modération.
      </Text>
      <EmailButton href={caseUrl}>Ouvrir le dossier</EmailButton>
    </EmailLayout>
  );
}

ReportCaseOpenedEmail.PreviewProps = {
  targetType: "comment",
  reason: "harassment",
  caseUrl: "https://admin.strava.echimine.fr/reports/00000000-0000-4000-8000-000000000000",
  logoUrl: PREVIEW_LOGO_URL,
} satisfies ReportCaseOpenedEmailProps;

export function renderReportCaseOpenedEmail(props: ReportCaseOpenedEmailProps): Promise<string> {
  return render(<ReportCaseOpenedEmail {...props} />);
}
