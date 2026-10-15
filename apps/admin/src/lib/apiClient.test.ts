import { meResponseSchema } from "@repo/contracts";
import { HttpResponse, http } from "msw";
import { describe, expect, it } from "vitest";
import { apiClient, ApiClientError } from "@/lib/apiClient";
import { server } from "@/test/msw-server";

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
  });
});
