import { screen, within } from "@testing-library/react";
import { HttpResponse, http } from "msw";
import { describe, expect, it, vi } from "vitest";
import type { AdminReportCaseListItem, AdminReportCaseListResponse } from "@repo/contracts";
import { server } from "@/test/msw-server";
import { renderWithProviders } from "@/test/render";
import { ReportsView } from "./ReportsView";

const params = vi.hoisted(() => ({ value: new URLSearchParams() }));
vi.mock("next/navigation", () => ({
  usePathname: () => "/reports",
  useRouter: () => ({ push: vi.fn(), replace: vi.fn() }),
  useSearchParams: () => params.value,
}));

const NOW = Date.now();
const hoursAgo = (hours: number) => new Date(NOW - hours * 3_600_000).toISOString();

const item = (overrides: Partial<AdminReportCaseListItem>): AdminReportCaseListItem => ({
  id: "c1c1c1c1-0000-4000-8000-000000000001",
  targetType: "comment",
  targetId: "d1d1d1d1-0000-4000-8000-000000000001",
  status: "open",
  openedAt: hoursAgo(30),
  closedAt: null,
  author: { id: "8d1b6c2a-1f3e-4a5b-9c7d-2e4f6a8b0c1d", displayName: "Émile Durand", avatarUrl: null },
  preview: "Commentaire haineux",
  reportCount: 3,
  reasons: ["spam", "harassment"],
  ...overrides,
});

function serve(items: AdminReportCaseListItem[], seen: URLSearchParams[] = []) {
  server.use(
    http.get("/api/v1/admin/reports", ({ request }) => {
      seen.push(new URL(request.url).searchParams);
      const page: AdminReportCaseListResponse = { items, total: items.length, page: 1, pageSize: 50 };
      return HttpResponse.json(page);
    }),
  );
  return seen;
}

/** The moderation queue (ADR-038 §10): one row per case, oldest first, red past 24 h. */
describe("ReportsView", () => {
  it("lists open cases with type, preview, author, count, reasons and a red badge past 24 h", async () => {
    params.value = new URLSearchParams();
    const seen = serve([
      item({}),
      item({
        id: "c1c1c1c1-0000-4000-8000-000000000002",
        targetType: "athlete",
        preview: "Paul Martin",
        openedAt: hoursAgo(2),
        reportCount: 1,
        reasons: ["impersonation"],
      }),
    ]);
    renderWithProviders(<ReportsView />);

    const link = await screen.findByRole("link", { name: "Commentaire haineux" });
    expect(link.getAttribute("href")).toBe("/reports/c1c1c1c1-0000-4000-8000-000000000001");
    const rows = screen.getAllByRole("row");
    const first = within(rows[1]!);
    expect(first.getByText("Commentaire")).toBeTruthy();
    expect(first.getByRole("link", { name: "Émile Durand" }).getAttribute("href")).toBe(
      "/users/8d1b6c2a-1f3e-4a5b-9c7d-2e4f6a8b0c1d",
    );
    expect(first.getByText("3")).toBeTruthy();
    expect(first.getByText("Spam ou publicité, Harcèlement ou propos haineux")).toBeTruthy();
    expect(first.getByText(/plus de 24 h/)).toBeTruthy();
    expect(within(rows[2]!).queryByText(/plus de 24 h/)).toBeNull();
    expect(within(rows[2]!).getByText("Profil")).toBeTruthy();
    expect(seen[0]!.get("state")).toBe("open");
  });

  it("« Clos » asks for the closed cases and shows their outcome", async () => {
    params.value = new URLSearchParams("state=closed");
    const seen = serve([item({ status: "dismissed", preview: null, closedAt: hoursAgo(1) })]);
    renderWithProviders(<ReportsView />);

    expect(await screen.findByText("Rejeté")).toBeTruthy();
    expect(seen[0]!.get("state")).toBe("closed");
  });
});
