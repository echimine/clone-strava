import { fireEvent, screen, within } from "@testing-library/react";
import { HttpResponse, http } from "msw";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { AuditEntry } from "@repo/contracts";
import { server } from "@/test/msw-server";
import { renderWithProviders } from "@/test/render";
import { JournalView } from "./JournalView";

const navigation = vi.hoisted(() => ({ search: new URLSearchParams(), push: vi.fn() }));
vi.mock("next/navigation", () => ({
  usePathname: () => "/journal",
  useRouter: () => ({ push: navigation.push, replace: navigation.push }),
  useSearchParams: () => navigation.search,
}));

const ADMIN = "3f6a9b0e-6e4c-4f7b-9e1a-6f7b2c3d4e5f";
const ATHLETE = "8d1b6c2a-1f3e-4a5b-9c7d-2e4f6a8b0c1d";
const GONE = "5e2c7a9b-3d4f-4e6a-8b1c-9d0e2f4a6b8c";

const ban: AuditEntry = {
  id: "a1a1a1a1-0000-4000-8000-000000000001",
  createdAt: "2026-11-02T09:30:00.000Z",
  action: "user.ban",
  actor: { id: ADMIN, displayName: "Alice Admin" },
  target: { type: "user", id: ATHLETE, exists: true },
  subject: { id: ATHLETE, displayName: "Émile Athlète" },
  reason: "Propos haineux",
  details: { duration: "7d" },
  requestId: "req-1",
};

const cleanup: AuditEntry = {
  id: "a1a1a1a1-0000-4000-8000-000000000002",
  createdAt: "2026-11-01T08:00:00.000Z",
  action: "user.delete.complete",
  actor: null,
  target: { type: "user", id: GONE, exists: false },
  subject: { id: GONE, displayName: null },
  reason: null,
  details: null,
  requestId: null,
};

function serve(entries: AuditEntry[], total = entries.length, onRequest?: (url: URL) => void) {
  server.use(
    http.get("/api/v1/admin/audit-entries", ({ request }) => {
      const url = new URL(request.url);
      onRequest?.(url);
      return HttpResponse.json({
        items: entries,
        total,
        page: Number(url.searchParams.get("page") ?? 1),
        pageSize: Number(url.searchParams.get("pageSize") ?? 50),
      });
    }),
    http.get("/api/v1/admin/audit-entries/actors", () =>
      HttpResponse.json({ items: [{ id: ADMIN, displayName: "Alice Admin" }] }),
    ),
  );
}

/** The Journal screen (ADR-038 §3): every admin action, filterable, newest first. */
describe("JournalView", () => {
  beforeEach(() => {
    navigation.search = new URLSearchParams();
    navigation.push.mockClear();
  });

  it("shows each entry with its author, action, target, athlete concerned and reason", async () => {
    serve([ban, cleanup]);
    renderWithProviders(<JournalView />);

    const banRow = (await screen.findByText("Propos haineux")).closest("tr")!;
    expect(within(banRow).getByText("Alice Admin")).toBeTruthy();
    expect(within(banRow).getByText("Bannissement")).toBeTruthy();
    expect(within(banRow).getByRole("link", { name: "Émile Athlète" }).getAttribute("href")).toBe(`/users/${ATHLETE}`);

    const cleanupRow = screen.getByText("Système").closest("tr")!;
    expect(within(cleanupRow).getByText("Suppression du compte terminée")).toBeTruthy();
    expect(within(cleanupRow).getAllByText("Compte supprimé").length).toBeGreaterThan(0);
    // A target that no longer exists is not a link.
    expect(within(cleanupRow).queryByRole("link")).toBeNull();
  });

  it("asks the API for the filters and page held in the URL", async () => {
    navigation.search = new URLSearchParams(
      `action=user.ban&actorId=${ADMIN}&from=2026-11-01&to=2026-11-04&page=2&pageSize=25`,
    );
    let asked: URL | undefined;
    serve([ban], 26, (url) => {
      asked = url;
    });
    renderWithProviders(<JournalView />);

    await screen.findByText("Propos haineux");
    expect(Object.fromEntries(asked!.searchParams)).toEqual({
      action: "user.ban",
      actorId: ADMIN,
      from: "2026-11-01",
      to: "2026-11-04",
      page: "2",
      pageSize: "25",
    });
  });

  it("goes to another page by its number", async () => {
    serve([ban], 120);
    renderWithProviders(<JournalView />);

    await screen.findByText("Propos haineux");
    expect(screen.getByText("120 entrées")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Page 3" }));

    expect(navigation.push).toHaveBeenCalledWith("/journal?page=3", { scroll: false });
  });

  it("filters by action, back to the first page", async () => {
    navigation.search = new URLSearchParams("page=4");
    serve([ban], 200);
    renderWithProviders(<JournalView />);

    fireEvent.change(await screen.findByLabelText("Action"), { target: { value: "comment.remove" } });

    expect(navigation.push).toHaveBeenCalledWith("/journal?action=comment.remove", { scroll: false });
  });

  it("filters on an athlete concerned from their entry, and clears it", async () => {
    serve([ban]);
    renderWithProviders(<JournalView />);

    fireEvent.click(await screen.findByRole("button", { name: "Filtrer sur Émile Athlète" }));
    expect(navigation.push).toHaveBeenCalledWith(`/journal?subjectUserId=${ATHLETE}`, { scroll: false });
  });
});
