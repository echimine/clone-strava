import { fireEvent, screen, waitFor, within } from "@testing-library/react";
import { HttpResponse, http } from "msw";
import { describe, expect, it, vi } from "vitest";
import type { AdminReportCaseDetail } from "@repo/contracts";
import { server } from "@/test/msw-server";
import { renderWithProviders } from "@/test/render";
import { ReportCaseView } from "./ReportCaseView";

vi.mock("next/navigation", () => ({
  usePathname: () => "/reports/x",
  useRouter: () => ({ push: vi.fn(), replace: vi.fn() }),
  useSearchParams: () => new URLSearchParams(),
}));
vi.mock("sonner", () => ({ toast: { success: vi.fn(), error: vi.fn() } }));

const CASE = "c1c1c1c1-0000-4000-8000-000000000001";
const COMMENT = "d1d1d1d1-0000-4000-8000-000000000001";
const ACTIVITY = "a1a1a1a1-0000-4000-8000-000000000001";
const MEDIA = "e1e1e1e1-0000-4000-8000-000000000001";
const EMILE = "8d1b6c2a-1f3e-4a5b-9c7d-2e4f6a8b0c1d";
const RITA = "5e2c7a9b-3d4f-4e6a-8b1c-9d0e2f4a6b8c";
const ADMIN = "9f9f9f9f-0000-4000-8000-000000000001";

const commentCase: AdminReportCaseDetail = {
  id: CASE,
  targetType: "comment",
  targetId: COMMENT,
  status: "open",
  openedAt: "2026-11-02T08:00:00.000Z",
  closedAt: null,
  closedBy: null,
  closeNote: null,
  current: {
    kind: "comment",
    body: "Texte modifié",
    createdAt: "2026-11-01T08:00:00.000Z",
    updatedAt: "2026-11-02T09:00:00.000Z",
    activity: { id: ACTIVITY, title: "Sortie du dimanche" },
  },
  author: {
    id: EMILE,
    displayName: "Émile Durand",
    avatarUrl: null,
    role: "user",
    banned: true,
    reportsReceived: 4,
    pastSanctions: 2,
  },
  reports: [
    {
      id: "b1b1b1b1-0000-4000-8000-000000000001",
      reporter: null,
      reason: "other",
      note: "Insultant",
      createdAt: "2026-11-02T08:00:00.000Z",
      copy: { kind: "comment", body: "Texte injurieux d'origine" },
      changedSince: true,
    },
    {
      id: "b1b1b1b1-0000-4000-8000-000000000002",
      reporter: { id: RITA, displayName: "Rita Lopez" },
      reason: "harassment",
      note: null,
      createdAt: "2026-11-02T10:00:00.000Z",
      copy: { kind: "comment", body: "Texte modifié" },
      changedSince: false,
    },
  ],
  canResolve: false,
};

function serve(detail: AdminReportCaseDetail) {
  server.use(http.get(`/api/v1/admin/reports/${CASE}`, () => HttpResponse.json(detail)));
}

/** A case of the moderation queue (ADR-038 §10): content now, copies, Reports, author, actions. */
describe("ReportCaseView", () => {
  it("shows the comment now with its Activity, each Report's copy when it changed, the reporters and the author", async () => {
    serve(commentCase);
    renderWithProviders(<ReportCaseView caseId={CASE} />);

    expect(await screen.findByText("Texte modifié", { selector: "p" })).toBeTruthy();
    expect(screen.getByRole("link", { name: "Sortie du dimanche" }).getAttribute("href")).toBe(`/activities/${ACTIVITY}`);
    expect(screen.getByText("modifié depuis le signalement")).toBeTruthy();
    expect(screen.getByText("Texte injurieux d'origine")).toBeTruthy();
    expect(screen.getByText("Compte supprimé")).toBeTruthy();
    expect(screen.getByRole("link", { name: "Rita Lopez" }).getAttribute("href")).toBe(`/users/${RITA}`);
    expect(screen.getByText("Insultant")).toBeTruthy();
    const author = within(screen.getByRole("region", { name: "Auteur" }));
    expect(author.getByRole("link", { name: "Émile Durand" }).getAttribute("href")).toBe(`/users/${EMILE}`);
    expect(author.getByText("Banni")).toBeTruthy();
    expect(author.getByText("4 signalements reçus · 2 Sanctions passées")).toBeTruthy();
  });

  it("removes the comment through its Sanction endpoint, with the reason", async () => {
    serve(commentCase);
    let body: unknown;
    server.use(
      http.delete(`/api/v1/admin/comments/${COMMENT}`, async ({ request }) => {
        body = await request.json();
        return new HttpResponse(null, { status: 204 });
      }),
    );
    renderWithProviders(<ReportCaseView caseId={CASE} />);

    fireEvent.click(await screen.findByRole("button", { name: "Retirer le commentaire" }));
    const dialog = within(screen.getByRole("dialog"));
    fireEvent.change(dialog.getByLabelText("Motif"), { target: { value: "Propos injurieux" } });
    fireEvent.click(dialog.getByRole("button", { name: "Retirer le commentaire" }));

    await waitFor(() => expect(body).toEqual({ reason: "Propos injurieux" }));
  });

  it("offers only « Rejeter » without a Sanction, and closes with the note", async () => {
    serve(commentCase);
    let closed: { path: string; body: unknown } | undefined;
    server.use(
      http.post(`/api/v1/admin/reports/${CASE}/:outcome`, async ({ request, params }) => {
        closed = { path: String(params.outcome), body: await request.json() };
        return HttpResponse.json({ id: CASE, status: "dismissed", closedAt: "2026-11-03T08:00:00.000Z", count: 2 });
      }),
    );
    renderWithProviders(<ReportCaseView caseId={CASE} />);

    fireEvent.click(await screen.findByRole("button", { name: "Clore" }));
    const dialog = within(screen.getByRole("dialog"));
    expect(dialog.getByRole("radio", { name: /Sanctionné/ }).hasAttribute("disabled")).toBe(true);
    expect(dialog.getByText(/aucune Sanction/)).toBeTruthy();
    fireEvent.change(dialog.getByLabelText("Note (facultative)"), { target: { value: "Rien d'anormal" } });
    fireEvent.click(dialog.getByRole("button", { name: "Clore le dossier" }));

    await waitFor(() => expect(closed).toEqual({ path: "dismiss", body: { note: "Rien d'anormal" } }));
  });

  it("closes as « Sanctionné » once a Sanction is in the Journal", async () => {
    serve({ ...commentCase, canResolve: true });
    let outcome: string | undefined;
    server.use(
      http.post(`/api/v1/admin/reports/${CASE}/:outcome`, ({ params }) => {
        outcome = String(params.outcome);
        return HttpResponse.json({ id: CASE, status: "actioned", closedAt: "2026-11-03T08:00:00.000Z", count: 2 });
      }),
    );
    renderWithProviders(<ReportCaseView caseId={CASE} />);

    fireEvent.click(await screen.findByRole("button", { name: "Clore" }));
    const dialog = within(screen.getByRole("dialog"));
    fireEvent.click(dialog.getByRole("radio", { name: /Sanctionné/ }));
    fireEvent.click(dialog.getByRole("button", { name: "Clore le dossier" }));

    await waitFor(() => expect(outcome).toBe("resolve"));
  });

  it("offers the Activity's Sanctions, and no Ban for an Administrator author", async () => {
    serve({
      ...commentCase,
      targetType: "activity",
      targetId: ACTIVITY,
      current: {
        kind: "activity",
        title: "Sortie",
        description: "Description",
        startedAt: "2026-11-01T08:00:00.000Z",
        media: [
          {
            id: MEDIA,
            kind: "photo",
            width: 10,
            height: 10,
            durationMs: null,
            url: "https://bucket.test/o.jpg",
            posterUrl: null,
            thumbUrl: "https://bucket.test/t.jpg",
          },
        ],
      },
      author: { ...commentCase.author, role: "admin", banned: false },
      reports: [],
    });
    renderWithProviders(<ReportCaseView caseId={CASE} />);

    expect(await screen.findByRole("button", { name: "Supprimer l'Activité" })).toBeTruthy();
    expect(screen.getByRole("button", { name: "Réinitialiser titre et description" })).toBeTruthy();
    expect(screen.getByRole("button", { name: "Retirer le Média 1" })).toBeTruthy();
    expect(screen.getByRole("link", { name: "Voir l'Activité" }).getAttribute("href")).toBe(`/activities/${ACTIVITY}`);
    expect(screen.queryByRole("button", { name: "Bannir l'auteur" })).toBeNull();
  });

  it("a closed case shows its outcome, who closed it and the note, without actions", async () => {
    serve({
      ...commentCase,
      status: "dismissed",
      closedAt: "2026-11-03T08:00:00.000Z",
      closedBy: { id: ADMIN, displayName: "Alice Admin" },
      closeNote: "Rien d'anormal",
      reports: commentCase.reports.map((report) => ({ ...report, copy: null, changedSince: false })),
      canResolve: false,
    });
    renderWithProviders(<ReportCaseView caseId={CASE} />);

    expect(await screen.findByText("Rejeté")).toBeTruthy();
    expect(screen.getByText(/Alice Admin/)).toBeTruthy();
    expect(screen.getByText("Rien d'anormal")).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Clore" })).toBeNull();
    expect(screen.queryByRole("button", { name: "Retirer le commentaire" })).toBeNull();
    expect(screen.queryByText("Texte injurieux d'origine")).toBeNull();
  });

  it("a case closed by the system says « Système »", async () => {
    serve({ ...commentCase, status: "target_gone", closedAt: "2026-11-03T08:00:00.000Z", current: null, canResolve: false });
    renderWithProviders(<ReportCaseView caseId={CASE} />);

    expect(await screen.findByText("Cible supprimée")).toBeTruthy();
    expect(screen.getByText(/Système/)).toBeTruthy();
    expect(screen.getByText("Le contenu signalé n'existe plus.")).toBeTruthy();
  });
});
