import type { SendEmailJob } from "@repo/contracts";
import { describe, expect, it } from "vitest";
import { renderEmailJob } from "./index.js";

const logoUrl = "https://admin.example.com/brand/nervo-wordmark-email.png";
const caseUrl = "https://admin.example.com/reports/0c7e7b8a-5d0e-4b8f-9a39-2a1f0f6f9b11";

function job(data: Partial<Extract<SendEmailJob, { template: "report-case-opened" }>["data"]> = {}): SendEmailJob {
  return {
    template: "report-case-opened",
    to: "admin@example.com",
    idempotencyKey: "report-case-0c7e7b8a-admin",
    userId: null,
    data: { targetType: "comment", reason: "harassment", caseUrl, ...data },
  };
}

function visibleText(html: string): string {
  return html
    .replace(/<!--[\s\S]*?-->/g, "")
    .replace(/<[^>]+>/g, " ")
    .replace(/&#x27;|&#39;/g, "'")
    .replace(/&nbsp;| /g, " ")
    .replace(/\s+/g, " ");
}

/** ADR-038 §10: the Administrators learn a case opened, with its type, reason and link. */
describe("new report case e-mail to an Administrator", () => {
  it("names the target type and the reason in French, and links to the case", async () => {
    const { subject, html } = await renderEmailJob(job(), { logoUrl, contactEmail: null });
    const text = visibleText(html);

    expect(subject).toBe("Nouveau signalement à traiter");
    expect(html).toContain('lang="fr"');
    expect(text).toContain("un commentaire");
    expect(text).toContain("Harcèlement ou propos haineux");
    expect(html).toContain(`href="${caseUrl}"`);
  });

  it.each([
    ["activity", "une Activité"],
    ["athlete", "un athlète"],
  ] as const)("names a %s target", async (targetType, label) => {
    const { html } = await renderEmailJob(job({ targetType, reason: "spam" }), { logoUrl, contactEmail: null });

    expect(visibleText(html)).toContain(label);
    expect(visibleText(html)).toContain("Spam ou publicité");
  });
});
