import { adminAccessResponseSchema, meResponseSchema } from "@repo/contracts";
import { HttpResponse, http } from "msw";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { apiClient, ApiClientError } from "@/lib/apiClient";
import { hardNavigate } from "@/lib/navigation";
import { server } from "@/test/msw-server";

// jsdom cannot follow a full page navigation: the browser boundary is observed instead.
vi.mock("@/lib/navigation", () => ({ hardNavigate: vi.fn() }));

describe("apiClient", () => {
  it("parses a successful JSON response with the given schema", async () => {
    server.use(
      http.get("/api/v1/me", () =>
        HttpResponse.json({
          id: "3f6a9b0e-6e4c-4f7b-9e1a-6f7b2c3d4e5f",
          email: "admin@example.com",
          name: "Admin",
          role: "admin",
          isPremium: false,
          defaultVisibility: "public",
          approveFollowers: false,
        }),
      ),
    );

    const me = await apiClient("/v1/me", meResponseSchema);

    expect(me.email).toBe("admin@example.com");
    expect(me.role).toBe("admin");
  });

  it("throws a normalized ApiClientError on a non-2xx response", async () => {
    server.use(
      http.get("/api/v1/me", () =>
        HttpResponse.json(
          { error: { code: "forbidden", message: "Accès refusé" } },
          { status: 403 },
        ),
      ),
    );

    await expect(apiClient("/v1/me", meResponseSchema)).rejects.toMatchObject({
      status: 403,
      code: "forbidden",
      message: "Accès refusé",
    } satisfies Partial<ApiClientError>);
    expect(hardNavigate).not.toHaveBeenCalled();
  });
});

/** ADR-022 §5 and ADR-035 §3: what the backoffice does with `AdminGuard`'s refusals. */
describe("apiClient on an admin route the session may not use", () => {
  beforeEach(() => {
    vi.mocked(hardNavigate).mockClear();
  });

  it("opens the 2FA setup screen on ADMIN_2FA_REQUIRED", async () => {
    server.use(
      http.get("/api/v1/admin", () =>
        HttpResponse.json(
          { error: { code: "ADMIN_2FA_REQUIRED", message: "2FA required" } },
          { status: 403 },
        ),
      ),
    );

    await expect(apiClient("/v1/admin", adminAccessResponseSchema)).rejects.toMatchObject({
      code: "ADMIN_2FA_REQUIRED",
    });
    expect(hardNavigate).toHaveBeenCalledWith("/two-factor/setup");
  });

  it("signs out, then goes back to the sign-in page on ADMIN_STRONG_SESSION_REQUIRED", async () => {
    const calls: string[] = [];
    server.use(
      http.get("/api/v1/admin", () => {
        calls.push("admin");
        return HttpResponse.json(
          { error: { code: "ADMIN_STRONG_SESSION_REQUIRED", message: "Sign in again" } },
          { status: 403 },
        );
      }),
      http.post("/api/auth/sign-out", () => {
        calls.push("sign-out");
        return HttpResponse.json({ success: true });
      }),
    );
    vi.mocked(hardNavigate).mockImplementation(() => calls.push("navigate"));

    await expect(apiClient("/v1/admin", adminAccessResponseSchema)).rejects.toMatchObject({
      code: "ADMIN_STRONG_SESSION_REQUIRED",
    });
    expect(calls).toEqual(["admin", "sign-out", "navigate"]);
    expect(hardNavigate).toHaveBeenCalledWith("/login?reason=strong-session");
  });
});
