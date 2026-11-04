import { Heading, Hr, Text } from "@react-email/components";
import type { EmailActivityLabel } from "@repo/contracts";
import type { ReactNode } from "react";
import { type BrandedEmailProps, EmailLayout } from "./email-layout.js";

/**
 * Pieces shared by the e-mails to an athlete (ADR-038 §4): French, transactional, no link and
 * no unsubscribe link, the reason quoted as typed, the team's address to reply to. Never a word
 * about a Report.
 */

const PARIS = "Europe/Paris";
const DAY = new Intl.DateTimeFormat("fr-FR", { day: "numeric", month: "long", year: "numeric", timeZone: PARIS });
const TIME = new Intl.DateTimeFormat("fr-FR", { hour: "2-digit", minute: "2-digit", timeZone: PARIS });

/** About 200 characters of a quoted comment (ADR-038 §4). */
const QUOTE_MAX_LENGTH = 200;

/** « 2 novembre 2026 », the Paris day of `iso`. */
export function parisDay(iso: string): string {
  return DAY.format(new Date(iso));
}

/** « 11 novembre 2026 à 14:30 », Paris time. */
export function parisDateTime(iso: string): string {
  const date = new Date(iso);
  return `${DAY.format(date)} à ${TIME.format(date)}`;
}

/** « votre Activité « Sortie du dimanche » du 2 novembre 2026 » without the possessive. */
export function activityLabel(activity: EmailActivityLabel): string {
  return `Activité « ${activity.title} » du ${parisDay(activity.startedAt)}`;
}

/** A comment quoted at most {@link QUOTE_MAX_LENGTH} characters, an ellipsis when cut. */
export function truncatedQuote(text: string): string {
  const trimmed = text.trim();
  const chars = [...trimmed];
  return chars.length > QUOTE_MAX_LENGTH ? `${chars.slice(0, QUOTE_MAX_LENGTH).join("").trimEnd()}…` : trimmed;
}

/** Props of every e-mail to an athlete. */
export interface AthleteEmailProps extends BrandedEmailProps {
  firstName: string | null;
  /** `CONTACT_EMAIL`, the Reply-To; null when not configured (replying still reaches nobody else). */
  contactEmail: string | null;
}

export interface AthleteEmailFrameProps extends AthleteEmailProps {
  preview: string;
  heading: string;
  /** The Sanction's reason; null for none (an athlete deleting their own account). */
  reason: string | null;
  /** Whether to end with the address to reply to (every Sanction does). */
  withContact: boolean;
  children: ReactNode;
}

const MUTED = { color: "#666666", fontSize: "13px" } as const;

/** Greeting, what happened (`children`), the reason, then how to contest. */
export function AthleteEmailFrame({
  preview,
  heading,
  firstName,
  reason,
  contactEmail,
  withContact,
  logoUrl,
  children,
}: AthleteEmailFrameProps) {
  return (
    <EmailLayout preview={preview} logoUrl={logoUrl} lang="fr">
      <Heading as="h1" style={{ fontSize: "22px" }}>
        {heading}
      </Heading>
      <Text>{firstName ? `Bonjour ${firstName},` : "Bonjour,"}</Text>
      {children}
      {reason !== null && (
        <>
          <Text style={{ marginBottom: "4px" }}>Motif indiqué par l'équipe Nervo :</Text>
          <Text style={{ marginTop: 0, fontStyle: "italic" }}>{`« ${reason} »`}</Text>
        </>
      )}
      {withContact && (
        <>
          <Hr />
          <Text style={MUTED}>
            {contactEmail
              ? `Répondez à cet e-mail pour contester cette décision ou poser une question : votre réponse parvient à l'équipe Nervo (${contactEmail}).`
              : "Répondez à cet e-mail pour contester cette décision ou poser une question."}
          </Text>
        </>
      )}
    </EmailLayout>
  );
}
