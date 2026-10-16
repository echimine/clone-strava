import { Body, Button, Container, Head, Html, Img, Preview, Section } from "@react-email/components";
import type { ReactNode } from "react";

/** Nervo orange, the app's `Theme.accent` (ADR-032 §2). */
const BRAND_ORANGE = "#FC5200";

/** Size of the wordmark PNG at 1x (the hosted file is 2x, 558 × 128, for retina). */
const WORDMARK_WIDTH = 140;
const WORDMARK_HEIGHT = 32;

export interface EmailLayoutProps {
  preview: string;
  /** Absolute public URL of the wordmark PNG (`apps/admin/public/brand/`). */
  logoUrl: string;
  children: ReactNode;
}

/**
 * Frame shared by every auth email: an orange band with the white NERVO
 * wordmark, then a white card. The wordmark is a hosted PNG since email
 * clients do not render SVG (ADR-032 §2).
 */
export function EmailLayout({ preview, logoUrl, children }: EmailLayoutProps) {
  return (
    <Html lang="en">
      <Head />
      <Preview>{preview}</Preview>
      <Body style={{ fontFamily: "sans-serif", backgroundColor: "#f6f6f6" }}>
        <Container style={{ backgroundColor: "#ffffff", borderRadius: "8px", overflow: "hidden" }}>
          <Section style={{ backgroundColor: BRAND_ORANGE, padding: "20px 32px" }}>
            <Img src={logoUrl} alt="Nervo" width={WORDMARK_WIDTH} height={WORDMARK_HEIGHT} />
          </Section>
          <Section style={{ padding: "32px" }}>{children}</Section>
        </Container>
      </Body>
    </Html>
  );
}

/** Call-to-action button of the auth emails, in Nervo orange. */
export function EmailButton({ href, children }: { href: string; children: ReactNode }) {
  return (
    <Button
      href={href}
      style={{
        backgroundColor: BRAND_ORANGE,
        color: "#ffffff",
        padding: "12px 20px",
        borderRadius: "4px",
        textDecoration: "none",
        boxSizing: "border-box",
      }}
    >
      {children}
    </Button>
  );
}

/** Wordmark URL used by the react-email previews (production admin). */
export const PREVIEW_LOGO_URL = "https://admin.strava.echimine.fr/brand/nervo-wordmark-email.png";
