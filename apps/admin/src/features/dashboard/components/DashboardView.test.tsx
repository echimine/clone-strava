import { fireEvent, screen, within } from "@testing-library/react";
import { HttpResponse, http } from "msw";
import { beforeAll, describe, expect, it } from "vitest";
import type { AdminGrowthStats, AdminTodoStats } from "@repo/contracts";
import { server } from "@/test/msw-server";
import { renderWithProviders } from "@/test/render";
import { DashboardView } from "./DashboardView";

const HOUR = 3_600_000;

const todo = (oldestOpenedAt: string | null): AdminTodoStats => ({
  openReports: { count: 3, oldestOpenedAt },
  failedActivities: 4,
  failedImports: 2,
  failedJobs: 7,
  suspiciousEfforts: 0,
});

const trend = (value: number, previous: number) => ({ value, previous });

function growth(period: AdminGrowthStats["period"]): AdminGrowthStats {
  return {
    period,
    from: "2026-10-06",
    to: "2026-11-04",
    signUps: trend(150, 100),
    activeAthletes: trend(80, 80),
    activities: { total: trend(410, 400), recorded: trend(300, 0), imported: trend(100, 100), manual: trend(10, 20) },
    premium: {
      payingActive: 12,
      trialsActive: 5,
      promotionalActive: 0,
      trialsStarted: trend(6, 3),
      newPaying: trend(2, 4),
    },
    engagement: { kudos: trend(900, 600), comments: trend(120, 100), follows: trend(60, 30), media: trend(40, 40) },
    daily: [
      { day: "2026-11-03", signUps: 4, activities: 12 },
      { day: "2026-11-04", signUps: 6, activities: 15 },
    ],
  };
}

function serve(todoStats: AdminTodoStats, onGrowth?: (url: URL) => void) {
  server.use(
    http.get("/api/v1/admin/stats/todo", () => HttpResponse.json(todoStats)),
    http.get("/api/v1/admin/stats/growth", ({ request }) => {
      const url = new URL(request.url);
      onGrowth?.(url);
      return HttpResponse.json(growth((url.searchParams.get("period") ?? "30d") as AdminGrowthStats["period"]));
    }),
  );
}

/** The backoffice dashboard (ADR-038 §15): "À traiter" now, "Croissance" over a period. */
describe("DashboardView", () => {
  beforeAll(() => {
    // Recharts measures its container; jsdom has no layout.
    globalThis.ResizeObserver ??= class {
      observe() {}
      unobserve() {}
      disconnect() {}
    };
  });

  it("shows the work waiting, open Reports linked to the queue, failures to the Jobs screen, other tiles without a link while their screen does not exist", async () => {
    serve(todo(new Date(Date.now() - 2 * HOUR).toISOString()));
    renderWithProviders(<DashboardView />);

    const band = await screen.findByRole("region", { name: "À traiter" });
    expect(await within(band).findByText("Signalements ouverts")).toBeTruthy();
    const tile = (label: string) => within(band).getByText(label).closest("[data-slot=card]") as HTMLElement;
    expect(within(tile("Signalements ouverts")).getByText("3")).toBeTruthy();
    expect(within(tile("Activités en échec")).getByText("4")).toBeTruthy();
    expect(within(tile("Imports en échec")).getByText("2")).toBeTruthy();
    expect(within(tile("Jobs en échec")).getByText("7")).toBeTruthy();
    expect(within(tile("Efforts à vérifier")).getByText("0")).toBeTruthy();
    expect(within(band).getAllByRole("link").map((link) => link.getAttribute("href"))).toEqual([
      "/reports",
      "/jobs",
      "/jobs",
      "/jobs?tab=files",
    ]);
    expect(within(tile("Efforts à vérifier")).queryByRole("link")).toBeNull();
    expect(within(tile("Signalements ouverts")).getByText(/il y a 2 heures/).className).not.toContain("text-destructive");
  });

  it("shows the oldest open Report in red past 24 hours", async () => {
    serve(todo(new Date(Date.now() - 30 * HOUR).toISOString()));
    renderWithProviders(<DashboardView />);

    const age = await screen.findByText(/il y a 1 jour/);
    expect(age.className).toContain("text-destructive");
  });

  it("shows the Growth over 30 days by default, with each change versus the previous period", async () => {
    const periods: (string | null)[] = [];
    serve(todo(null), (url) => periods.push(url.searchParams.get("period")));
    renderWithProviders(<DashboardView />);

    const band = await screen.findByRole("region", { name: "Croissance" });
    const tile = async (label: string) =>
      (await within(band).findByText(label)).closest("[data-slot=card]") as HTMLElement;
    const signUps = await tile("Inscriptions");
    expect(within(signUps).getByText("150")).toBeTruthy();
    expect(within(signUps).getByText("+50 %")).toBeTruthy();
    expect(within(await tile("Nouveaux payants")).getByText("−50 %")).toBeTruthy();
    expect(within(await tile("Activités")).getByText(/300 enregistrées · 100 importées · 10 saisies/)).toBeTruthy();
    expect(within(await tile("Premium offerts actifs")).getByText("0")).toBeTruthy();
    expect(periods).toEqual(["30d"]);
    expect(screen.getByRole("button", { name: "30 j" }).getAttribute("aria-pressed")).toBe("true");
  });

  it("switches the period", async () => {
    const periods: (string | null)[] = [];
    serve(todo(null), (url) => periods.push(url.searchParams.get("period")));
    renderWithProviders(<DashboardView />);
    await screen.findByText("Inscriptions");

    fireEvent.click(screen.getByRole("button", { name: "7 j" }));

    await screen.findByRole("button", { name: "7 j", pressed: true });
    expect(periods).toContain("7d");
  });

  it("links to PostHog for the app's usage", async () => {
    serve(todo(null));
    renderWithProviders(<DashboardView />);

    const link = await screen.findByRole("link", { name: /Ouvrir PostHog/ });
    expect(link.getAttribute("href")).toMatch(/^https:\/\/eu\.posthog\.com\//);
  });
});
