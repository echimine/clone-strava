import { fireEvent, screen, waitFor, within } from "@testing-library/react";
import { HttpResponse, http } from "msw";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { AdminActivityDetail } from "@repo/contracts";
import { server } from "@/test/msw-server";
import { renderWithProviders } from "@/test/render";
import { ActivityDetailView } from "./ActivityDetailView";

const navigation = vi.hoisted(() => ({ push: vi.fn() }));
vi.mock("next/navigation", () => ({
  usePathname: () => "/activities/x",
  useRouter: () => ({ push: navigation.push, replace: navigation.push }),
  useSearchParams: () => new URLSearchParams(),
}));
vi.mock("sonner", () => ({ toast: { success: vi.fn(), error: vi.fn() } }));

const ID = "c1c1c1c1-0000-4000-8000-000000000001";
const EMILE = "8d1b6c2a-1f3e-4a5b-9c7d-2e4f6a8b0c1d";
const ZOE = "5e2c7a9b-3d4f-4e6a-8b1c-9d0e2f4a6b8c";
const COMMENT = "d1d1d1d1-0000-4000-8000-000000000001";
const MEDIA = "e1e1e1e1-0000-4000-8000-000000000001";

const processed: AdminActivityDetail = {
  id: ID,
  title: "Sortie du dimanche",
  description: "Belle sortie",
  athlete: { id: EMILE, displayName: "Émile Durand", avatarUrl: null },
  sportTypeCode: "run",
  visibility: "public",
  source: "imported",
  processingStatus: "processed",
  processingError: null,
  processingAttempts: 1,
  startedAt: "2026-11-02T08:00:00.000Z",
  endedAt: "2026-11-02T09:00:00.000Z",
  createdAt: "2026-11-02T10:00:00.000Z",
  updatedAt: "2026-11-02T10:00:00.000Z",
  processedAt: "2026-11-02T10:00:05.000Z",
  stats: {
    distanceM: 10012.5,
    movingTimeS: 3000,
    elapsedTimeS: 3600,
    elevationGainM: 120,
    avgSpeedMs: 3.3,
    maxSpeedMs: 5,
    avgHeartRate: null,
    maxHeartRate: null,
    calories: null,
  },
  route: [
    [2.35, 48.85],
    [2.36, 48.86],
  ],
  locationName: "Paris",
  media: [
    {
      id: MEDIA,
      kind: "photo",
      width: 100,
      height: 100,
      durationMs: null,
      url: "https://bucket.test/original.jpg",
      posterUrl: null,
      thumbUrl: "https://bucket.test/thumb.jpg",
    },
  ],
  comments: [
    {
      id: COMMENT,
      author: { id: ZOE, displayName: "Zoé Martin", avatarUrl: null },
      body: "Commentaire haineux",
      createdAt: "2026-11-02T12:00:00.000Z",
      updatedAt: null,
    },
  ],
  commentCount: 1,
  kudos: [{ athlete: { id: ZOE, displayName: "Zoé Martin", avatarUrl: null }, createdAt: "2026-11-02T13:00:00.000Z" }],
  kudosCount: 1,
  import: {
    id: ID,
    format: "gpx",
    fileName: "sortie.gpx",
    status: "imported",
    activityId: ID,
    createdAt: "2026-11-02T09:59:00.000Z",
  },
  efforts: [
    {
      id: "f1f1f1f1-0000-4000-8000-000000000001",
      segmentId: "f2f2f2f2-0000-4000-8000-000000000001",
      segmentName: "Côte du Mont",
      elapsedTimeS: 420,
      startedAt: "2026-11-02T08:10:00.000Z",
      rank: 3,
    },
  ],
};

function serve(detail: AdminActivityDetail) {
  server.use(http.get(`/api/v1/admin/activities/${ID}`, () => HttpResponse.json(detail)));
}

/** The backoffice detail of an Activity and its actions (ADR-038 §11). */
describe("ActivityDetailView", () => {
  beforeEach(() => navigation.push.mockClear());

  it("shows the official values, the athlete, comments, kudos, import and efforts", async () => {
    serve(processed);
    renderWithProviders(<ActivityDetailView id={ID} />);

    expect(await screen.findByRole("heading", { name: "Sortie du dimanche" })).toBeTruthy();
    expect(screen.getByRole("link", { name: "Émile Durand" }).getAttribute("href")).toBe(`/users/${EMILE}`);
    expect(screen.getByText("10,01 km")).toBeTruthy();
    expect(screen.getByText("50 min")).toBeTruthy();
    expect(screen.getByText("Commentaire haineux")).toBeTruthy();
    expect(screen.getByText("Kudos (1)")).toBeTruthy();
    expect(screen.getByText(/sortie\.gpx/)).toBeTruthy();
    expect(screen.getByText("Côte du Mont")).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Retraiter" })).toBeNull();
  });

  it("offers « Retraiter » on a failed Activity only, and shows the worker's error", async () => {
    serve({ ...processed, processingStatus: "failed", processingError: "invalid_trace", stats: null, route: null });
    let reprocessed = false;
    server.use(
      http.post(`/api/v1/admin/activities/${ID}/reprocess`, () => {
        reprocessed = true;
        return HttpResponse.json({ id: ID, processingStatus: "processing" }, { status: 202 });
      }),
    );
    renderWithProviders(<ActivityDetailView id={ID} />);

    expect(await screen.findByText("invalid_trace")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Retraiter" }));

    await waitFor(() => expect(reprocessed).toBe(true));
  });

  it("deletes the Activity with a reason, then goes back to the list", async () => {
    serve(processed);
    let body: unknown;
    server.use(
      http.delete(`/api/v1/admin/activities/${ID}`, async ({ request }) => {
        body = await request.json();
        return new HttpResponse(null, { status: 204 });
      }),
    );
    renderWithProviders(<ActivityDetailView id={ID} />);

    fireEvent.click(await screen.findByRole("button", { name: "Supprimer l'Activité" }));
    const dialog = await screen.findByRole("dialog");
    expect(within(dialog).getByText("Ce motif sera lu par l'athlète.")).toBeTruthy();
    fireEvent.change(within(dialog).getByLabelText("Motif"), { target: { value: "Contenu choquant" } });
    fireEvent.click(within(dialog).getByRole("button", { name: "Supprimer" }));

    await waitFor(() => expect(navigation.push).toHaveBeenCalledWith("/activities"));
    expect(body).toEqual({ reason: "Contenu choquant" });
  });

  it("removes a comment with a reason", async () => {
    serve(processed);
    let body: unknown;
    server.use(
      http.delete(`/api/v1/admin/comments/${COMMENT}`, async ({ request }) => {
        body = await request.json();
        return new HttpResponse(null, { status: 204 });
      }),
    );
    renderWithProviders(<ActivityDetailView id={ID} />);

    const comment = (await screen.findByText("Commentaire haineux")).closest("li")!;
    fireEvent.click(within(comment).getByRole("button", { name: "Retirer" }));
    const dialog = await screen.findByRole("dialog");
    fireEvent.change(within(dialog).getByLabelText("Motif"), { target: { value: "Harcèlement" } });
    fireEvent.click(within(dialog).getByRole("button", { name: "Retirer le commentaire" }));

    await waitFor(() => expect(body).toEqual({ reason: "Harcèlement" }));
  });

  it("removes a Media and resets the text with a reason", async () => {
    serve(processed);
    const calls: string[] = [];
    server.use(
      http.delete(`/api/v1/admin/activities/${ID}/media/${MEDIA}`, () => {
        calls.push("media");
        return new HttpResponse(null, { status: 204 });
      }),
      http.post(`/api/v1/admin/activities/${ID}/reset-text`, () => {
        calls.push("reset");
        return HttpResponse.json({ id: ID, title: "Course à pied le matin", description: null });
      }),
    );
    renderWithProviders(<ActivityDetailView id={ID} />);

    fireEvent.click(await screen.findByRole("button", { name: "Retirer le Média 1" }));
    let dialog = await screen.findByRole("dialog");
    fireEvent.change(within(dialog).getByLabelText("Motif"), { target: { value: "Photo inappropriée" } });
    fireEvent.click(within(dialog).getByRole("button", { name: "Retirer le Média" }));
    await waitFor(() => expect(calls).toEqual(["media"]));
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());

    fireEvent.click(screen.getByRole("button", { name: "Réinitialiser titre et description" }));
    dialog = await screen.findByRole("dialog");
    fireEvent.change(within(dialog).getByLabelText("Motif"), { target: { value: "Propos haineux" } });
    fireEvent.click(within(dialog).getByRole("button", { name: "Réinitialiser" }));
    await waitFor(() => expect(calls).toEqual(["media", "reset"]));
  });
});
