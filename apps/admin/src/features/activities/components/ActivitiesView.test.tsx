import { fireEvent, screen, within } from "@testing-library/react";
import { HttpResponse, http } from "msw";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { AdminActivityListItem } from "@repo/contracts";
import { server } from "@/test/msw-server";
import { renderWithProviders } from "@/test/render";
import { ActivitiesView } from "./ActivitiesView";

const navigation = vi.hoisted(() => ({ search: new URLSearchParams(), push: vi.fn() }));
vi.mock("next/navigation", () => ({
  usePathname: () => "/activities",
  useRouter: () => ({ push: navigation.push, replace: navigation.push }),
  useSearchParams: () => navigation.search,
}));

const EMILE = "8d1b6c2a-1f3e-4a5b-9c7d-2e4f6a8b0c1d";

const failedRide: AdminActivityListItem = {
  id: "c1c1c1c1-0000-4000-8000-000000000001",
  title: "Sortie du dimanche",
  athlete: { id: EMILE, displayName: "Émile Durand", avatarUrl: null },
  sportTypeCode: "ride",
  processingStatus: "failed",
  source: "imported",
  visibility: "private",
  startedAt: "2026-11-02T08:00:00.000Z",
  createdAt: "2026-11-02T10:00:00.000Z",
  distanceM: null,
};

function serve(items: AdminActivityListItem[], onRequest?: (url: URL) => void) {
  server.use(
    http.get("/api/v1/admin/activities", ({ request }) => {
      const url = new URL(request.url);
      onRequest?.(url);
      return HttpResponse.json({ items, total: items.length, page: 1, pageSize: 50 });
    }),
  );
}

/** The backoffice Activities list (ADR-038 §11). */
describe("ActivitiesView", () => {
  beforeEach(() => {
    navigation.search = new URLSearchParams();
    navigation.push.mockClear();
  });

  it("shows each Activity with its athlete, sport, status, source and visibility", async () => {
    serve([failedRide]);
    renderWithProviders(<ActivitiesView />);

    const row = (await screen.findByRole("link", { name: "Sortie du dimanche" })).closest("tr")!;
    expect(screen.getByRole("link", { name: "Sortie du dimanche" }).getAttribute("href")).toBe(
      `/activities/${failedRide.id}`,
    );
    expect(within(row).getByRole("link", { name: "Émile Durand" }).getAttribute("href")).toBe(`/users/${EMILE}`);
    expect(within(row).getByText("Vélo")).toBeTruthy();
    expect(within(row).getByText("Échec")).toBeTruthy();
    expect(within(row).getByText("Importée")).toBeTruthy();
    expect(within(row).getByText("Privée")).toBeTruthy();
  });

  it("sends the filters of the URL to the API", async () => {
    navigation.search = new URLSearchParams(`status=failed&source=imported&userId=${EMILE}&q=dimanche&page=2`);
    let requested: URL | undefined;
    serve([failedRide], (url) => (requested = url));
    renderWithProviders(<ActivitiesView />);

    await screen.findByText("Sortie du dimanche");
    expect(Object.fromEntries(requested!.searchParams)).toEqual({
      page: "2",
      pageSize: "50",
      q: "dimanche",
      status: "failed",
      source: "imported",
      userId: EMILE,
    });
  });

  it("puts a chosen filter in the URL, back to the first page", async () => {
    navigation.search = new URLSearchParams("page=3");
    serve([failedRide]);
    renderWithProviders(<ActivitiesView />);
    await screen.findByText("Sortie du dimanche");

    fireEvent.change(screen.getByLabelText("Statut"), { target: { value: "failed" } });

    expect(navigation.push).toHaveBeenCalledWith("/activities?status=failed", { scroll: false });
  });

  it("names the athlete whose Activities are shown, and can drop that filter", async () => {
    navigation.search = new URLSearchParams(`userId=${EMILE}`);
    serve([failedRide]);
    renderWithProviders(<ActivitiesView />);

    fireEvent.click(await screen.findByRole("button", { name: "Retirer le filtre sur l'athlète" }));

    expect(navigation.push).toHaveBeenCalledWith("/activities", { scroll: false });
  });
});
