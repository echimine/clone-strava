import { fireEvent, screen } from "@testing-library/react";
import { HttpResponse, http } from "msw";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { AuditEntry } from "@repo/contracts";
import { server } from "@/test/msw-server";
import { renderWithProviders } from "@/test/render";
import { AuditHistory } from "./AuditHistory";

const navigation = vi.hoisted(() => ({ search: new URLSearchParams(), push: vi.fn() }));
vi.mock("next/navigation", () => ({
  usePathname: () => "/users/8d1b6c2a-1f3e-4a5b-9c7d-2e4f6a8b0c1d",
  useRouter: () => ({ push: navigation.push, replace: navigation.push }),
  useSearchParams: () => navigation.search,
}));

const ATHLETE = "8d1b6c2a-1f3e-4a5b-9c7d-2e4f6a8b0c1d";

const unban: AuditEntry = {
  id: "a1a1a1a1-0000-4000-8000-000000000003",
  createdAt: "2026-11-03T09:30:00.000Z",
  action: "user.unban",
  actor: { id: "3f6a9b0e-6e4c-4f7b-9e1a-6f7b2c3d4e5f", displayName: "Alice Admin" },
  target: { type: "user", id: ATHLETE, exists: true },
  subject: { id: ATHLETE, displayName: "Émile Athlète" },
  reason: "Erreur de modération",
  details: null,
  requestId: null,
};

/** "Historique" of a user sheet (ADR-038 §3): the entries whose athlete concerned they are. */
describe("AuditHistory", () => {
  beforeEach(() => {
    navigation.search = new URLSearchParams();
    navigation.push.mockClear();
  });

  it("lists the athlete's entries, with its own page in the URL", async () => {
    let asked: URL | undefined;
    server.use(
      http.get("/api/v1/admin/audit-entries", ({ request }) => {
        asked = new URL(request.url);
        return HttpResponse.json({ items: [unban], total: 30, page: 1, pageSize: 25 });
      }),
    );
    navigation.search = new URLSearchParams("page=7");
    renderWithProviders(<AuditHistory subjectUserId={ATHLETE} />);

    expect(await screen.findByText("Erreur de modération")).toBeTruthy();
    expect(screen.getByText("Levée du bannissement")).toBeTruthy();
    // The sheet's own list keeps its `page`; the Historique pages with `historyPage`.
    expect(Object.fromEntries(asked!.searchParams)).toEqual({ subjectUserId: ATHLETE, page: "1", pageSize: "25" });

    fireEvent.click(screen.getByRole("button", { name: "Page 2" }));
    expect(navigation.push).toHaveBeenCalledWith(
      `/users/${ATHLETE}?page=7&historyPage=2`,
      { scroll: false },
    );
  });

  it("says when nothing was ever done about the athlete", async () => {
    server.use(
      http.get("/api/v1/admin/audit-entries", () =>
        HttpResponse.json({ items: [], total: 0, page: 1, pageSize: 25 }),
      ),
    );
    renderWithProviders(<AuditHistory subjectUserId={ATHLETE} />);

    expect(await screen.findByText("Aucune entrée.")).toBeTruthy();
  });
});
