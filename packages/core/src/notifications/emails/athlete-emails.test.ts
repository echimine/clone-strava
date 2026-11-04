import type { SendEmailJob } from "@repo/contracts";
import { describe, expect, it } from "vitest";
import { renderEmailJob } from "./index.js";

const logoUrl = "https://admin.example.com/brand/nervo-wordmark-email.png";
const contactEmail = "contact@strava.echimine.fr";
const base = { to: "lea@example.com", idempotencyKey: "0c7e7b8a-5d0e-4b8f-9a39-2a1f0f6f9b11", userId: null };
const sortie = { title: "Sortie du dimanche", startedAt: "2026-11-02T08:30:00.000Z" };

/** The text a reader sees, tags and entities aside. */
function visibleText(html: string): string {
  return html
    .replace(/<!--[\s\S]*?-->/g, "")
    .replace(/<[^>]+>/g, " ")
    .replace(/&#x27;|&#39;/g, "'")
    .replace(/&quot;/g, '"')
    .replace(/&nbsp;| /g, " ")
    .replace(/&amp;/g, "&")
    .replace(/\s+/g, " ");
}

async function rendered(job: SendEmailJob, contact: string | null = contactEmail) {
  const { subject, html } = await renderEmailJob(job, { logoUrl, contactEmail: contact });
  return { subject, html, text: visibleText(html) };
}

const sanctions: Array<[string, SendEmailJob]> = [
  ["ban", { ...base, template: "user-banned", data: { firstName: "Léa", reason: "Propos injurieux", until: null } }],
  ["unban", { ...base, template: "user-unbanned", data: { firstName: "Léa", reason: "Erreur de modération" } }],
  [
    "content removed",
    { ...base, template: "content-removed", data: { firstName: "Léa", reason: "Hors sujet", content: { kind: "activity", activity: sortie } } },
  ],
  ["profile reset", { ...base, template: "profile-reset", data: { firstName: "Léa", reason: "Bio injurieuse", field: "bio" } }],
  ["account deleted by an Administrator", { ...base, template: "account-deleted", data: { firstName: "Léa", reason: "Spam" } }],
];

/** ADR-038 §4: what every e-mail after a Sanction says, whatever its family. */
describe("e-mails to a sanctioned athlete", () => {
  it.each(sanctions)("%s: French, greets the athlete, quotes the reason as typed", async (_name, job) => {
    const { html, text } = await rendered(job);

    expect(html).toContain('lang="fr"');
    expect(text).toContain("Bonjour Léa,");
    expect(text).toContain(`« ${(job.data as { reason: string }).reason} »`);
  });

  it.each(sanctions)("%s: gives the contact address and how to contest", async (_name, job) => {
    const { text } = await rendered(job);

    expect(text).toContain(contactEmail);
    expect(text).toContain("Répondez à cet e-mail pour contester");
  });

  it.each(sanctions)("%s: no link, no unsubscribe, never a word about a Report", async (_name, job) => {
    const { html, text } = await rendered(job);

    expect(html).not.toMatch(/<a\s/);
    expect(text).not.toMatch(/désinscri|signalement|signaleur/i);
  });

  it.each(sanctions)("%s: branded Nervo, wordmark on the orange band", async (_name, job) => {
    const { html } = await rendered(job);

    expect(/<img[^>]*>/.exec(html)?.[0]).toContain(`src="${logoUrl}"`);
    expect(html).toContain("background-color:#FC5200");
  });

  it("without a contact address, still says to reply, and greets without a first name", async () => {
    const { text } = await rendered(
      { ...base, template: "user-unbanned", data: { firstName: null, reason: "Erreur" } },
      null,
    );

    expect(text).toContain("Bonjour,");
    expect(text).toContain("Répondez à cet e-mail pour contester");
  });
});

describe("Ban e-mail", () => {
  it("gives the end of a temporary Ban, Paris time", async () => {
    const { subject, text } = await rendered({
      ...base,
      template: "user-banned",
      data: { firstName: "Léa", reason: "Spam", until: "2026-11-11T13:30:00.000Z" },
    });

    expect(subject).toBe("Votre compte Nervo est suspendu");
    expect(text).toContain("jusqu'au 11 novembre 2026 à 14:30 (heure de Paris)");
  });

  it("says « définitivement » for a permanent Ban", async () => {
    const { text } = await rendered({ ...base, template: "user-banned", data: { firstName: "Léa", reason: "Spam", until: null } });

    expect(text).toContain("définitivement");
  });
});

describe("Ban lifted e-mail", () => {
  it("says the account is usable again", async () => {
    const { subject, text } = await rendered({ ...base, template: "user-unbanned", data: { firstName: "Léa", reason: "Erreur" } });

    expect(subject).toBe("La suspension de votre compte Nervo est levée");
    expect(text).toContain("Vous pouvez de nouveau vous connecter");
  });
});

describe("Content removed e-mail", () => {
  const removed = (content: Extract<SendEmailJob, { template: "content-removed" }>["data"]["content"]) =>
    rendered({ ...base, template: "content-removed", data: { firstName: "Léa", reason: "Hors sujet", content } });

  it("names the Activity by title and Paris day, without a link", async () => {
    const { subject, text } = await removed({ kind: "activity", activity: sortie });

    expect(subject).toBe("Un contenu de votre compte Nervo a été retiré");
    expect(text).toContain("votre Activité « Sortie du dimanche » du 2 novembre 2026 a été retirée");
  });

  it("names the Activity a Media was removed from", async () => {
    const { text } = await removed({ kind: "media", activity: sortie });

    expect(text).toContain("une photo ou une vidéo de votre Activité « Sortie du dimanche » du 2 novembre 2026 a été retirée");
  });

  it("names the Activity whose title and description were reset, by its former title", async () => {
    const { text } = await removed({ kind: "activity-text", activity: sortie });

    expect(text).toContain("le titre et la description de votre Activité « Sortie du dimanche » du 2 novembre 2026 ont été réinitialisés");
  });

  it("quotes a removed comment, with its day and Activity", async () => {
    const { text } = await removed({
      kind: "comment",
      body: "Quelle allure de tortue",
      postedAt: "2026-11-03T21:00:00.000Z",
      activity: sortie,
    });

    expect(text).toContain("votre commentaire du 3 novembre 2026 sur l'Activité « Sortie du dimanche » a été retiré");
    expect(text).toContain("« Quelle allure de tortue »");
  });

  it("truncates a long comment to about 200 characters", async () => {
    const { text } = await removed({ kind: "comment", body: "a".repeat(500), postedAt: null, activity: null });

    expect(text).toContain(`« ${"a".repeat(200)}… »`);
    expect(text).not.toContain("a".repeat(201));
    expect(text).toContain("votre commentaire a été retiré");
  });
});

describe("Profile reset e-mail", () => {
  it.each([
    ["name", "votre nom a été remplacé par « Athlète »"],
    ["bio", "votre bio a été effacée"],
    ["avatar", "votre photo de profil a été retirée"],
  ] as const)("names the %s reset", async (field, sentence) => {
    const { subject, text } = await rendered({ ...base, template: "profile-reset", data: { firstName: "Léa", reason: "x", field } });

    expect(subject).toBe("Votre profil Nervo a été modifié");
    expect(text).toContain(sentence);
  });
});

/** ADR-038 §13: one e-mail in both cases, reason and contact only for a Sanction. */
describe("Account deleted e-mail", () => {
  it("by the athlete: no reason, no contact line", async () => {
    const { subject, text } = await rendered({ ...base, template: "account-deleted", data: { firstName: "Léa", reason: null } });

    expect(subject).toBe("Votre compte Nervo a été supprimé");
    expect(text).toContain("Votre compte Nervo et ses données ont été supprimés");
    expect(text).not.toContain("Motif");
    expect(text).not.toContain(contactEmail);
  });

  it("by an Administrator: the reason and the contact", async () => {
    const { text } = await rendered({ ...base, template: "account-deleted", data: { firstName: "Léa", reason: "Spam" } });

    expect(text).toContain("« Spam »");
    expect(text).toContain(contactEmail);
  });
});
