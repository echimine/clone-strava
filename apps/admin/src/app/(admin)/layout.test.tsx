import { screen, waitFor } from "@testing-library/react";
import { HttpResponse, http } from "msw";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { hardNavigate } from "@/lib/navigation";
import { server } from "@/test/msw-server";
import { renderWithProviders } from "@/test/render";
import AdminLayout from "./layout";

vi.mock("@/lib/navigation", () => ({ hardNavigate: vi.fn() }));
vi.mock("next/navigation", () => ({
  usePathname: () => "/",
  useRouter: () => ({ replace: vi.fn() }),
}));
// jsdom has no matchMedia; the sidebar reads it to pick its mobile layout.
vi.stubGlobal("matchMedia", (query: string) => ({
  matches: false,
  media: query,
  addEventListener: () => {},
  removeEventListener: () => {},
}));

const admin = {
  id: "3f6a9b0e-6e4c-4f7b-9e1a-6f7b2c3d4e5f",
  email: "admin@example.com",
  name: "Admin",
  role: "admin",
  isPremium: false,
  defaultVisibility: "public",
  approveFollowers: false,
};

/** The admin pages open only once `/v1/admin` accepts the session (ADR-022 §5, ADR-035 §3). */
describe("(admin) layout", () => {
  beforeEach(() => {
    vi.mocked(hardNavigate).mockClear();
  });

  it("shows the page once the session may use the admin routes", async () => {
    server.use(
      http.get("/api/v1/me", () => HttpResponse.json(admin)),
      http.get("/api/v1/admin", () => HttpResponse.json({ status: "ok" })),
    );

    renderWithProviders(<AdminLayout>Tableau</AdminLayout>);

    expect(await screen.findByText("Tableau")).toBeTruthy();
  });

  it("sends an admin without 2FA to the setup screen, without showing the page", async () => {
    server.use(
      http.get("/api/v1/me", () => HttpResponse.json(admin)),
      http.get("/api/v1/admin", () =>
        HttpResponse.json(
          { error: { code: "ADMIN_2FA_REQUIRED", message: "2FA required" } },
          { status: 403 },
        ),
      ),
    );

    renderWithProviders(<AdminLayout>Tableau</AdminLayout>);

    await waitFor(() => expect(hardNavigate).toHaveBeenCalledWith("/two-factor/setup"));
    expect(screen.queryByText("Tableau")).toBeNull();
  });
});
