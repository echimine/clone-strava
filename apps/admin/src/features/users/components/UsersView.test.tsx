import { fireEvent, screen, waitFor, within } from "@testing-library/react";
import { HttpResponse, http } from "msw";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { AdminUserListItem } from "@repo/contracts";
import { server } from "@/test/msw-server";
import { renderWithProviders } from "@/test/render";
import { UsersView } from "./UsersView";

const navigation = vi.hoisted(() => ({ search: new URLSearchParams(), push: vi.fn() }));
vi.mock("next/navigation", () => ({
  usePathname: () => "/users",
  useRouter: () => ({ push: navigation.push, replace: navigation.push }),
  useSearchParams: () => navigation.search,
}));

const EMILE = "8d1b6c2a-1f3e-4a5b-9c7d-2e4f6a8b0c1d";

const bannedEmile: AdminUserListItem = {
  athlete: { id: EMILE, displayName: "Émile Durand", avatarUrl: null },
  email: "emile@example.com",
  role: "user",
  createdAt: "2026-01-02T10:00:00.000Z",
  signInMethods: ["email_code"],
  activityCount: 12,
  lastActivityAt: null,
  isPremium: true,
  state: "temporarily_banned",
  ban: { until: "2026-11-11T13:30:00.000Z", reason: "Spam" },
};

/** The backoffice users list (ADR-038 §5). */
describe("UsersView", () => {
  beforeEach(() => {
    navigation.search = new URLSearchParams();
    navigation.push.mockClear();
  });

  it("shows each account with e-mail, sign-in methods, Activities, Premium and Ban end", async () => {
    let url: URL | undefined;
    server.use(
      http.get("/api/v1/admin/users", ({ request }) => {
        url = new URL(request.url);
        return HttpResponse.json({ items: [bannedEmile], total: 1, page: 1, pageSize: 50 });
      }),
    );
    navigation.search = new URLSearchParams("state=temporarily_banned&sort=lastActivityAt");
    renderWithProviders(<UsersView />);

    const link = await screen.findByRole("link", { name: /Émile Durand/ });
    expect(link.getAttribute("href")).toBe(`/users/${EMILE}`);
    const row = link.closest("tr")!;
    expect(within(row).getByText("emile@example.com")).toBeTruthy();
    expect(within(row).getByText("Code e-mail")).toBeTruthy();
    expect(within(row).getByText("12")).toBeTruthy();
    expect(within(row).getByText("Premium")).toBeTruthy();
    expect(within(row).getByText("Banni jusqu'au 11/11/2026 14:30")).toBeTruthy();
    expect(url?.searchParams.get("state")).toBe("temporarily_banned");
    expect(url?.searchParams.get("sort")).toBe("lastActivityAt");
  });

  it("puts a filter in the URL and goes back to the first page", async () => {
    server.use(http.get("/api/v1/admin/users", () => HttpResponse.json({ items: [], total: 0, page: 1, pageSize: 50 })));
    renderWithProviders(<UsersView />);

    expect(await screen.findByText("Aucun utilisateur.")).toBeTruthy();
    fireEvent.change(screen.getByLabelText("Connexion"), { target: { value: "google" } });
    await waitFor(() => expect(navigation.push).toHaveBeenCalledWith("/users?method=google", { scroll: false }));
  });
});
