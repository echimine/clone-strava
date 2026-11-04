import { fireEvent, screen, waitFor, within } from "@testing-library/react";
import { HttpResponse, http } from "msw";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type {
  AdminFailedActivity,
  AdminFailedImport,
  AdminQueue,
  AdminQueueJob,
  AdminQueueJobDetail,
  AdminStaleActivity,
} from "@repo/contracts";
import { server } from "@/test/msw-server";
import { renderWithProviders } from "@/test/render";
import { JobsView } from "./JobsView";

const navigation = vi.hoisted(() => ({ search: new URLSearchParams(), push: vi.fn() }));
vi.mock("next/navigation", () => ({
  usePathname: () => "/jobs",
  useRouter: () => ({ push: navigation.push, replace: navigation.push }),
  useSearchParams: () => navigation.search,
}));

const EMILE = { id: "8d1b6c2a-1f3e-4a5b-9c7d-2e4f6a8b0c1d", displayName: "Émile Durand", avatarUrl: null };
const ACTIVITY_ID = "c1c1c1c1-0000-4000-8000-000000000001";

const failedActivity: AdminFailedActivity = {
  id: ACTIVITY_ID,
  title: "Sortie du dimanche",
  athlete: EMILE,
  sportTypeCode: "ride",
  processingError: "invalid_trace",
  processingAttempts: 5,
  startedAt: "2026-11-02T08:00:00.000Z",
  createdAt: "2026-11-02T10:00:00.000Z",
};
const failedImport: AdminFailedImport = {
  id: "d2d2d2d2-0000-4000-8000-000000000002",
  athlete: EMILE,
  format: "gpx",
  fileName: "marathon.gpx",
  error: "processing_error",
  attempts: 5,
  createdAt: "2026-11-02T10:00:00.000Z",
  processedAt: "2026-11-02T10:05:00.000Z",
};
const staleActivity: AdminStaleActivity = {
  id: "e3e3e3e3-0000-4000-8000-000000000003",
  title: "Rando",
  athlete: EMILE,
  sportTypeCode: "hike",
  computedForSportTypeCode: "run",
  startedAt: "2026-11-01T08:00:00.000Z",
  updatedAt: "2026-11-03T08:00:00.000Z",
};

const page = <T,>(items: T[], total = items.length) => ({ items, total, page: 1, pageSize: 50 });

function serveFailures(posts: string[] = []) {
  server.use(
    http.get("/api/v1/admin/failures/activities", () => HttpResponse.json(page([failedActivity], 2))),
    http.get("/api/v1/admin/failures/imports", () => HttpResponse.json(page([failedImport]))),
    http.get("/api/v1/admin/failures/recomputes", () => HttpResponse.json(page([staleActivity]))),
    http.post("/api/v1/admin/*", ({ request }) => {
      posts.push(new URL(request.url).pathname);
      return HttpResponse.json({ relaunched: 2, id: ACTIVITY_ID, processingStatus: "processing" }, { status: 202 });
    }),
  );
}

const counts = { waiting: 0, active: 0, delayed: 0, prioritized: 0, waitingChildren: 0, completed: 12, failed: 0 };
const queues: AdminQueue[] = [
  {
    name: "activities",
    isPaused: false,
    counts: { ...counts, failed: 3 },
    schedulers: [
      {
        id: "reconcile-activities",
        jobName: "reconcile-activities",
        everyMs: 600_000,
        pattern: null,
        timeZone: null,
        nextRunAt: "2026-11-04T10:10:00.000Z",
      },
    ],
  },
  { name: "imports", isPaused: true, counts, schedulers: [] },
  { name: "emails", isPaused: false, counts: { ...counts, completed: 0 }, schedulers: [] },
];
const processJob: AdminQueueJob = {
  id: `process-activity-${ACTIVITY_ID}`,
  name: "process-activity",
  queue: "activities",
  failedReason: "trace unreadable",
  attemptsMade: 5,
  maxAttempts: 5,
  createdAt: "2026-11-02T10:00:00.000Z",
  processedAt: "2026-11-02T10:00:01.000Z",
  finishedAt: "2026-11-02T10:10:00.000Z",
  retryRefused: true,
};
const reprocessJob: AdminQueueJob = {
  ...processJob,
  id: `reprocess-${ACTIVITY_ID}-1`,
  name: "reprocess-activity",
  failedReason: "timeout",
  retryRefused: false,
};

function serveQueues(posts: string[] = []) {
  server.use(
    http.get("/api/v1/admin/queues", () => HttpResponse.json({ items: queues })),
    http.get("/api/v1/admin/queues/activities/jobs", () => HttpResponse.json(page([processJob, reprocessJob]))),
    http.get("/api/v1/admin/queues/activities/jobs/:id", ({ params }) => {
      const detail: AdminQueueJobDetail = {
        ...(params.id === reprocessJob.id ? reprocessJob : processJob),
        state: "failed",
        stacktrace: ["Error: trace unreadable\n    at process (processor.js:12)"],
        data: { activityId: ACTIVITY_ID, userId: EMILE.id },
        activityId: ACTIVITY_ID,
        userId: EMILE.id,
      };
      return HttpResponse.json(detail);
    }),
    http.post("/api/v1/admin/queues/*", ({ request }) => {
      posts.push(new URL(request.url).pathname);
      return new HttpResponse(null, { status: 204 });
    }),
  );
}

/** The Jobs screen (ADR-038 §14): "Échecs" (business view) and "Files" (technical view). */
describe("JobsView", () => {
  beforeEach(() => {
    navigation.search = new URLSearchParams();
    navigation.push.mockClear();
  });

  describe("Échecs", () => {
    it("opens on the failed Activities, imports and recomputations, each linked to its Activity and athlete", async () => {
      serveFailures();
      renderWithProviders(<JobsView />);

      const activityRow = (await screen.findByRole("link", { name: "Sortie du dimanche" })).closest("tr")!;
      expect(within(activityRow).getByRole("link", { name: "Sortie du dimanche" }).getAttribute("href")).toBe(
        `/activities/${ACTIVITY_ID}`,
      );
      expect(within(activityRow).getAllByRole("link", { name: "Émile Durand" })[0]!.getAttribute("href")).toBe(
        `/users/${EMILE.id}`,
      );
      expect(within(activityRow).getByText("invalid_trace")).toBeTruthy();
      expect(within(activityRow).getByText("5")).toBeTruthy();

      const importRow = (await screen.findByText("marathon.gpx")).closest("tr")!;
      expect(within(importRow).getByText("processing_error")).toBeTruthy();

      const recomputeRow = screen.getByRole("link", { name: "Rando" }).closest("tr")!;
      expect(within(recomputeRow).getByText(/Course à pied/)).toBeTruthy();
      expect(within(recomputeRow).getByRole("button", { name: "Recalculer" })).toBeTruthy();
    });

    it("relaunches one failure through its domain action", async () => {
      const posts: string[] = [];
      serveFailures(posts);
      renderWithProviders(<JobsView />);

      const row = (await screen.findByRole("link", { name: "Sortie du dimanche" })).closest("tr")!;
      fireEvent.click(within(row).getByRole("button", { name: "Retraiter" }));
      fireEvent.click(within(screen.getByText("Rando").closest("tr")!).getByRole("button", { name: "Recalculer" }));
      fireEvent.click(within(screen.getByText("marathon.gpx").closest("tr")!).getByRole("button", { name: "Retraiter" }));

      await waitFor(() =>
        expect(posts.sort()).toEqual(
          [
            `/api/v1/admin/activities/${ACTIVITY_ID}/reprocess`,
            `/api/v1/admin/activities/${staleActivity.id}/recompute`,
            `/api/v1/admin/activity-imports/${failedImport.id}/reprocess`,
          ].sort(),
        ),
      );
    });

    it("« Retraiter les N en échec » asks to confirm the count, then relaunches the batch", async () => {
      const posts: string[] = [];
      serveFailures(posts);
      renderWithProviders(<JobsView />);

      fireEvent.click(await screen.findByRole("button", { name: "Retraiter les 2 en échec" }));
      const dialog = await screen.findByRole("alertdialog");
      expect(within(dialog).getByText(/2 Activités en échec seront renvoyées en traitement/)).toBeTruthy();
      expect(posts).toEqual([]);

      fireEvent.click(within(dialog).getByRole("button", { name: "Retraiter" }));

      await waitFor(() => expect(posts).toEqual(["/api/v1/admin/activities/reprocess-failed"]));
      expect(await screen.findByText("2 relancé(s)")).toBeTruthy();
    });
  });

  describe("Files", () => {
    it("shows each queue's counts, pause state and schedulers, and pauses or resumes it", async () => {
      navigation.search = new URLSearchParams("tab=files");
      const posts: string[] = [];
      serveQueues(posts);
      renderWithProviders(<JobsView />);

      const activities = (await screen.findByRole("cell", { name: "activities" })).closest("tr")!;
      expect(within(activities).getByRole("button", { name: "3 en échec" })).toBeTruthy();
      expect(screen.getByText(/reconcile-activities/)).toBeTruthy();
      expect(screen.getByText(/toutes les 10 min/)).toBeTruthy();
      const imports = screen.getByRole("cell", { name: "imports" }).closest("tr")!;
      expect(within(imports).getByText("En pause")).toBeTruthy();

      fireEvent.click(within(activities).getByRole("button", { name: "Mettre en pause" }));
      fireEvent.click(within(imports).getByRole("button", { name: "Reprendre" }));

      await waitFor(() =>
        expect(posts.sort()).toEqual(["/api/v1/admin/queues/activities/pause", "/api/v1/admin/queues/imports/resume"]),
      );
    });

    it("lists a queue's failed jobs; a refused retry points to « Retraiter », the detail opens read-only", async () => {
      navigation.search = new URLSearchParams("tab=files&queue=activities");
      const posts: string[] = [];
      serveQueues(posts);
      renderWithProviders(<JobsView />);

      const refused = (await screen.findByText("trace unreadable")).closest("tr")!;
      expect(within(refused).queryByRole("button", { name: "Relancer" })).toBeNull();
      expect(within(refused).getByText(/Retraiter depuis Échecs/)).toBeTruthy();

      const retriable = screen.getByText("timeout").closest("tr")!;
      fireEvent.click(within(retriable).getByRole("button", { name: "Relancer" }));
      await waitFor(() =>
        expect(posts).toEqual([`/api/v1/admin/queues/activities/jobs/${encodeURIComponent(reprocessJob.id)}/retry`]),
      );

      fireEvent.click(within(refused).getByRole("button", { name: "Détail" }));
      const dialog = await screen.findByRole("dialog");
      expect(await within(dialog).findByText(/"activityId":/)).toBeTruthy();
      // The stack trace is folded.
      expect(within(dialog).queryByText(/at process \(processor.js:12\)/)).toBeNull();
      fireEvent.click(within(dialog).getByRole("button", { name: "Pile d'appels" }));
      expect(await within(dialog).findByText(/at process \(processor.js:12\)/)).toBeTruthy();
      expect(within(dialog).getByRole("link", { name: "Voir l'Activité" }).getAttribute("href")).toBe(
        `/activities/${ACTIVITY_ID}`,
      );
      expect(within(dialog).getByRole("link", { name: "Voir l'athlète" }).getAttribute("href")).toBe(`/users/${EMILE.id}`);
    });
  });
});
