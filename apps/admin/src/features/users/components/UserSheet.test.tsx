import { fireEvent, screen, waitFor, within } from "@testing-library/react";
import { HttpResponse, http } from "msw";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { AdminUserDetail, AdminUserReportsResponse } from "@repo/contracts";
import { server } from "@/test/msw-server";
import { renderWithProviders } from "@/test/render";
import { UserSheet } from "./UserSheet";

const router = vi.hoisted(() => ({ push: vi.fn(), replace: vi.fn() }));
vi.mock("next/navigation", () => ({
  usePathname: () => "/users/x",
  useRouter: () => router,
  useSearchParams: () => new URLSearchParams(),
}));
vi.mock("sonner", () => ({ toast: { success: vi.fn(), error: vi.fn() } }));

const ID = "8d1b6c2a-1f3e-4a5b-9c7d-2e4f6a8b0c1d";
const CASE = "c1c1c1c1-0000-4000-8000-000000000001";

const athlete: AdminUserDetail = {
  athlete: { id: ID, displayName: "Émile Durand", avatarUrl: null },
  email: "emile@example.com",
  role: "user",
  createdAt: "2026-01-02T10:00:00.000Z",
  state: "active",
  ban: null,
  premium: { active: true, billedByAppStore: true },
  account: { signInMethods: ["google"], twoFactorEnabled: false },
  profile: {
    firstName: "Émile",
    lastName: "Durand",
    bio: "Traileur",
    city: "Annecy",
    country: "FR",
    sports: ["run"],
    level: "advanced",
    defaultVisibility: "followers",
  },
  activity: { activityCount: 12, lastActivityAt: "2026-11-02T08:00:00.000Z", streakWeeks: 3 },
  follows: { followerCount: 4, followingCount: 5, blockedByCount: 2 },
};

const reports: AdminUserReportsResponse = {
  received: [
    {
      id: "d1d1d1d1-0000-4000-8000-000000000001",
      caseId: CASE,
      targetType: "comment",
      reason: "harassment",
      status: "open",
      createdAt: "2026-11-03T08:00:00.000Z",
    },
  ],
  sent: [],
};

function serve(detail: AdminUserDetail) {
  server.use(
    http.get(`/api/v1/admin/users/${ID}`, () => HttpResponse.json(detail)),
    http.get(`/api/v1/admin/users/${ID}/sessions`, () =>
      HttpResponse.json({
        items: [
          {
            id: "s1",
            device: "App iOS",
            userAgent: "Nervo/1 CFNetwork/1 Darwin/25",
            createdAt: "2026-11-01T08:00:00.000Z",
            expiresAt: "2026-11-08T08:00:00.000Z",
          },
        ],
      }),
    ),
    http.get(`/api/v1/admin/users/${ID}/reports`, () => HttpResponse.json(reports)),
  );
}

/** The user sheet (ADR-038 §5): eight sections and the account's Sanctions. */
describe("UserSheet", () => {
  beforeEach(() => serve(athlete));

  it("shows the eight sections, the Premium and History slots, never birth date, gender or weight", async () => {
    renderWithProviders(<UserSheet id={ID} premium={<p>Premium de #215</p>} history={<p>Historique du Journal</p>} />);

    expect(await screen.findByRole("heading", { name: "Émile Durand" })).toBeTruthy();
    for (const title of ["Compte", "Profil d'athlète", "Activité", "Follows", "Premium", "Signalements", "Historique"]) {
      expect(screen.getByRole("heading", { name: title })).toBeTruthy();
    }
    expect(screen.getByText("Premium de #215")).toBeTruthy();
    expect(screen.getByText("Historique du Journal")).toBeTruthy();
    expect(screen.getByText("Bloqué par 2 athlètes")).toBeTruthy();
    expect(screen.getByText("3 semaines")).toBeTruthy();
    expect(screen.getByRole("link", { name: "Voir ses Activités" }).getAttribute("href")).toBe(`/activities?userId=${ID}`);
    expect(await screen.findByText("App iOS")).toBeTruthy();
    expect(screen.queryByText(/naissance|poids|sexe/i)).toBeNull();

    const caseLink = await screen.findByRole("link", { name: "Ouvrir le dossier" });
    expect(caseLink.getAttribute("href")).toBe(`/reports/${CASE}`);
    expect(screen.getByText("Harcèlement ou propos haineux")).toBeTruthy();
  });

  it("bans for 7 days with a reason, repeating the end and warning that Apple keeps billing", async () => {
    let body: unknown;
    server.use(
      http.post(`/api/v1/admin/users/${ID}/ban`, async ({ request }) => {
        body = await request.json();
        return new HttpResponse(null, { status: 204 });
      }),
    );
    renderWithProviders(<UserSheet id={ID} history={null} />);

    fireEvent.click(await screen.findByRole("button", { name: "Bannir" }));
    const dialog = await screen.findByRole("dialog");
    expect(within(dialog).getByRole("note").textContent).toContain("Apple continue de le facturer");
    fireEvent.change(within(dialog).getByLabelText("Durée"), { target: { value: "7d" } });
    expect(within(dialog).getByText(/^jusqu'au /)).toBeTruthy();
    fireEvent.change(within(dialog).getByLabelText("Motif"), { target: { value: "Propos haineux" } });
    fireEvent.click(within(dialog).getByRole("button", { name: "Bannir" }));

    await waitFor(() => expect(body).toEqual({ duration: "7d", reason: "Propos haineux" }));
  });

  it("an Administrator has no Ban button; the role change needs the e-mail typed again", async () => {
    serve({ ...athlete, role: "admin", account: { signInMethods: ["password"], twoFactorEnabled: true } });
    let body: unknown;
    server.use(
      http.put(`/api/v1/admin/users/${ID}/role`, async ({ request }) => {
        body = await request.json();
        return new HttpResponse(null, { status: 204 });
      }),
    );
    renderWithProviders(<UserSheet id={ID} history={null} />);

    await screen.findByText("Activée");
    expect(screen.queryByRole("button", { name: "Bannir" })).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "Retirer le rôle administrateur" }));
    const dialog = await screen.findByRole("dialog");
    const confirm = within(dialog).getByRole("button", { name: "Retirer le rôle" });
    expect((confirm as HTMLButtonElement).disabled).toBe(true);
    fireEvent.change(within(dialog).getByLabelText("Retapez l'e-mail du compte pour confirmer"), {
      target: { value: "emile@example.com" },
    });
    expect((confirm as HTMLButtonElement).disabled).toBe(false);
    fireEvent.click(confirm);

    await waitFor(() => expect(body).toEqual({ role: "user" }));
  });

  it("lifts an active Ban and resets the bio, each with a reason", async () => {
    serve({ ...athlete, state: "banned", ban: { until: null, reason: "Spam" } });
    const calls: unknown[] = [];
    server.use(
      http.post(`/api/v1/admin/users/${ID}/unban`, async ({ request }) => {
        calls.push(["unban", await request.json()]);
        return new HttpResponse(null, { status: 204 });
      }),
      http.post(`/api/v1/admin/users/${ID}/reset-bio`, async ({ request }) => {
        calls.push(["reset-bio", await request.json()]);
        return new HttpResponse(null, { status: 204 });
      }),
    );
    renderWithProviders(<UserSheet id={ID} history={null} />);

    expect(await screen.findByText("Banni définitivement")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Lever le Ban" }));
    let dialog = await screen.findByRole("dialog");
    fireEvent.change(within(dialog).getByLabelText("Motif"), { target: { value: "Erreur" } });
    fireEvent.click(within(dialog).getByRole("button", { name: "Lever le Ban" }));
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());

    fireEvent.click(screen.getByRole("button", { name: "Vider la bio" }));
    dialog = await screen.findByRole("dialog");
    fireEvent.change(within(dialog).getByLabelText("Motif"), { target: { value: "Publicité" } });
    fireEvent.click(within(dialog).getByRole("button", { name: "Vider" }));

    await waitFor(() =>
      expect(calls).toEqual([
        ["unban", { reason: "Erreur" }],
        ["reset-bio", { reason: "Publicité" }],
      ]),
    );
  });

  it("deletes the account as a Sanction once the athlete's name is typed, warning that Apple keeps billing", async () => {
    let body: unknown;
    server.use(
      http.delete(`/api/v1/admin/users/${ID}`, async ({ request }) => {
        body = await request.json();
        return new HttpResponse(null, { status: 204 });
      }),
    );
    renderWithProviders(<UserSheet id={ID} history={null} />);

    fireEvent.click(await screen.findByRole("button", { name: "Supprimer le compte" }));
    const dialog = await screen.findByRole("dialog");
    expect(within(dialog).getByText(/de façon définitive/)).toBeTruthy();
    expect(within(dialog).getByRole("note").textContent).toContain("Apple continue de le facturer");
    const confirm = within(dialog).getByRole("button", { name: "Supprimer définitivement" });
    fireEvent.change(within(dialog).getByLabelText("Motif"), { target: { value: "Demande de l'athlète" } });
    expect((confirm as HTMLButtonElement).disabled).toBe(true);
    fireEvent.change(within(dialog).getByLabelText("Tapez le nom de l'athlète pour confirmer"), {
      target: { value: "Émile Durand" },
    });
    expect((confirm as HTMLButtonElement).disabled).toBe(false);
    fireEvent.click(confirm);

    await waitFor(() => expect(body).toEqual({ reason: "Demande de l'athlète" }));
    await waitFor(() => expect(router.push).toHaveBeenCalledWith("/users"));
  });

  it("an Administrator's account has no « Supprimer le compte »", async () => {
    serve({ ...athlete, role: "admin", account: { signInMethods: ["password"], twoFactorEnabled: true } });
    renderWithProviders(<UserSheet id={ID} history={null} />);
    await screen.findByText("Activée");
    expect(screen.queryByRole("button", { name: "Supprimer le compte" })).toBeNull();
  });

  it("says when the account does not exist", async () => {
    server.use(
      http.get(`/api/v1/admin/users/${ID}`, () =>
        HttpResponse.json({ error: { code: "user_not_found", message: "User not found" } }, { status: 404 }),
      ),
    );
    renderWithProviders(<UserSheet id={ID} history={null} />);
    expect(await screen.findByText("Utilisateur introuvable.")).toBeTruthy();
  });
});
