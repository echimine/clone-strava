import { describe, expect, it, vi } from "vitest";
import { formatPlace } from "./domain/format-place.js";
import { GeocodingService } from "./geocoding.service.js";

const annecy = {
  properties: {
    name: "Annecy",
    context: { place: { name: "Annecy" }, region: { name: "Haute-Savoie" }, country: { name: "France" } },
  },
};

describe("formatPlace", () => {
  it("joins place and region", () => {
    expect(formatPlace(annecy)).toBe("Annecy, Haute-Savoie");
  });

  it("falls back to locality, country, then the place alone", () => {
    expect(formatPlace({ properties: { context: { locality: { name: "Talloires" }, country: { name: "France" } } } })).toBe(
      "Talloires, France",
    );
    expect(formatPlace({ properties: { name: "Monaco", context: { country: { name: "Monaco" } } } })).toBe("Monaco");
    expect(formatPlace(undefined)).toBeNull();
  });
});

describe("GeocodingService", () => {
  const point = { lat: 45.8992, lon: 6.1294 };

  it("is a no-op without a token", async () => {
    const fetchMock = vi.fn();
    const service = new GeocodingService({ fetch: fetchMock });
    expect(await service.reverse(point)).toBeNull();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("formats the first feature and asks for a permanent result", async () => {
    const fetchMock = vi.fn(async (_url: URL) => new Response(JSON.stringify({ features: [annecy] })));
    const service = new GeocodingService({
      accessToken: "sk.test",
      permanent: true,
      fetch: fetchMock as unknown as typeof fetch,
    });
    expect(await service.reverse(point)).toBe("Annecy, Haute-Savoie");
    const url = fetchMock.mock.calls[0]![0];
    expect(url.searchParams.get("permanent")).toBe("true");
    expect(url.searchParams.get("longitude")).toBe("6.12940");
  });

  it("returns null on HTTP errors and network failures", async () => {
    const failing = new GeocodingService({
      accessToken: "sk.test",
      fetch: vi.fn(async () => new Response("nope", { status: 401 })),
    });
    expect(await failing.reverse(point)).toBeNull();
    const throwing = new GeocodingService({
      accessToken: "sk.test",
      fetch: vi.fn(async () => {
        throw new Error("timeout");
      }),
    });
    expect(await throwing.reverse(point)).toBeNull();
  });
});
