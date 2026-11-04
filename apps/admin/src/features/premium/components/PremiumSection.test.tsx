import { fireEvent, screen, waitFor, within } from "@testing-library/react";
import { HttpResponse, http } from "msw";
import { describe, expect, it, vi } from "vitest";
import type { AdminUserPremium } from "@repo/contracts";
import { server } from "@/test/msw-server";
import { renderWithProviders } from "@/test/render";
import { PremiumSection } from "./PremiumSection";

vi.mock("sonner", () => ({ toast: { success: vi.fn(), error: vi.fn() } }));

const ID = "8d1b6c2a-1f3e-4a5b-9c7d-2e4f6a8b0c1d";

const cancelled: AdminUserPremium = {
  configured: true,
  state: "cancelled",
  detail: {
    productId: "nervo_monthly",
    store: "app_store",
    periodType: "normal",
    purchasedAt: "2026-10-01T08:00:00.000Z",
    expiresAt: "2026-12-01T08:00:00.000Z",
    gracePeriodExpiresAt: null,
    willRenew: false,
    unsubscribeDetectedAt: "2026-10-20T08:00:00.000Z",
    billingIssueDetectedAt: null,
    sandbox: true,
    syncedAt: "2026-10-20T08:05:00.000Z",
  },
  history: [
    {
      id: "evt-2",
      type: "CANCELLATION",
      occurredAt: "2026-10-20T08:00:00.000Z",
      productId: "nervo_monthly",
      store: "APP_STORE",
      periodType: "NORMAL",
      expiresAt: null,
      sandbox: true,
    },
    {
      id: "evt-1",
      type: "NON_RENEWING_PURCHASE",
      occurredAt: "2026-09-01T08:00:00.000Z",
      productId: null,
      store: "PROMOTIONAL",
      periodType: "PROMOTIONAL",
      expiresAt: "2026-10-01T08:00:00.000Z",
      sandbox: false,
    },
  ],
  revenueCatUrl: `https://app.revenuecat.com/projects/proj/customers/${ID}`,
};

function serve(premium: AdminUserPremium) {
  server.use(http.get(`/api/v1/admin/users/${ID}/premium`, () => HttpResponse.json(premium)));
}

/** The user sheet's « Premium » section (ADR-038 §12). */
describe("PremiumSection", () => {
  it("shows the state, the detail, the Sandbox badge, the RevenueCat link and the history by source", async () => {
    serve(cancelled);
    renderWithProviders(<PremiumSection userId={ID} />);

    expect(await screen.findByText("Résilié jusqu'au 01/12/2026")).toBeTruthy();
    expect(screen.getAllByText("Sandbox").length).toBeGreaterThan(0);
    expect(screen.getByText("Renouvellement automatique").nextElementSibling?.textContent).toBe("Non");
    expect(screen.getByRole("link", { name: "Voir dans RevenueCat" }).getAttribute("href")).toBe(cancelled.revenueCatUrl);
    expect(screen.getByText("Résiliation")).toBeTruthy();
    expect(screen.getByText("App Store · Payant")).toBeTruthy();
    expect(screen.getByText("Achat sans renouvellement")).toBeTruthy();
    expect(screen.getByText("Offert")).toBeTruthy();
    // Never « Abonnement », and no raw JSON.
    expect(screen.queryByText(/abonnement$/i)).toBeNull();
    expect(screen.queryByRole("button", { name: "Retirer le Premium offert" })).toBeNull();
  });

  it("offers Premium for 6 months with a reason the athlete does not read", async () => {
    serve({ ...cancelled, state: "never", detail: null, history: [] });
    let body: unknown;
    server.use(
      http.post(`/api/v1/admin/users/${ID}/premium/promotional`, async ({ request }) => {
        body = await request.json();
        return new HttpResponse(null, { status: 204 });
      }),
    );
    renderWithProviders(<PremiumSection userId={ID} />);

    expect(await screen.findByText("Jamais abonné")).toBeTruthy();
    expect(screen.getByText("Aucun événement RevenueCat.")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Offrir le Premium" }));
    const dialog = await screen.findByRole("dialog");
    fireEvent.change(within(dialog).getByLabelText("Durée"), { target: { value: "6m" } });
    expect(within(dialog).getByText("6 mois", { selector: "strong" })).toBeTruthy();
    expect(within(dialog).getByText(/aucun e-mail/)).toBeTruthy();
    expect(within(dialog).queryByText("Ce motif sera lu par l'athlète.")).toBeNull();
    fireEvent.change(within(dialog).getByLabelText("Motif"), { target: { value: "Testeur bêta" } });
    fireEvent.click(within(dialog).getByRole("button", { name: "Offrir" }));

    await waitFor(() => expect(body).toEqual({ duration: "6m", reason: "Testeur bêta" }));
  });

  it("takes a Promotional Premium back and resynchronises", async () => {
    serve({
      ...cancelled,
      state: "promotional",
      detail: { ...cancelled.detail!, store: "promotional", periodType: "promotional", productId: null, sandbox: false },
    });
    const calls: unknown[] = [];
    server.use(
      http.delete(`/api/v1/admin/users/${ID}/premium/promotional`, async ({ request }) => {
        calls.push(["revoke", await request.json()]);
        return new HttpResponse(null, { status: 204 });
      }),
      http.post(`/api/v1/admin/users/${ID}/premium/sync`, () => {
        calls.push(["sync"]);
        return HttpResponse.json({ queued: true }, { status: 202 });
      }),
    );
    renderWithProviders(<PremiumSection userId={ID} />);

    expect(await screen.findByText("Premium offert jusqu'au 01/12/2026")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Retirer le Premium offert" }));
    const dialog = await screen.findByRole("dialog");
    fireEvent.change(within(dialog).getByLabelText("Motif"), { target: { value: "Fin du partenariat" } });
    fireEvent.click(within(dialog).getByRole("button", { name: "Retirer" }));
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());

    fireEvent.click(screen.getByRole("button", { name: "Resynchroniser" }));
    await waitFor(() => expect(calls).toEqual([["revoke", { reason: "Fin du partenariat" }], ["sync"]]));
  });

  it("without RevenueCat the three actions are disabled: « RevenueCat non configuré »", async () => {
    serve({
      ...cancelled,
      configured: false,
      revenueCatUrl: null,
      state: "promotional",
      detail: { ...cancelled.detail!, store: "promotional", periodType: "promotional" },
    });
    renderWithProviders(<PremiumSection userId={ID} />);

    expect(await screen.findByText("RevenueCat non configuré")).toBeTruthy();
    for (const name of ["Resynchroniser", "Offrir de nouveau", "Retirer le Premium offert"]) {
      expect((screen.getByRole("button", { name }) as HTMLButtonElement).disabled).toBe(true);
    }
    expect(screen.queryByRole("link", { name: "Voir dans RevenueCat" })).toBeNull();
  });
});
