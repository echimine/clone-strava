import type { AddressInfo } from "node:net";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { OPEN_DATA_SEGMENTS_KEY } from "@repo/contracts";
import { StorageService } from "@repo/core/storage";
import { bootstrapAthleteApp, type AthleteApp } from "../testing/athlete-app.js";
import type { InMemoryStorage } from "../testing/in-memory-storage.js";

/**
 * `GET /v1/open-data/segments.ndjson.gz` (ADR-039 §10, §12): public, no session, redirects to the
 * weekly ODbL file of the bucket, cacheable.
 */
describe("GET /v1/open-data/segments.ndjson.gz", () => {
  let ctx: AthleteApp;
  let storage: InMemoryStorage;
  let url: string;

  beforeAll(async () => {
    ctx = await bootstrapAthleteApp();
    storage = ctx.app.get(StorageService) as unknown as InMemoryStorage;
    const { port } = ctx.app.getHttpServer().address() as AddressInfo;
    url = `http://127.0.0.1:${port}/v1/open-data/segments.ndjson.gz`;
  }, 30_000);

  afterAll(async () => {
    await ctx.close();
  });

  it("answers 404 before the first weekly export", async () => {
    storage.objects.delete(OPEN_DATA_SEGMENTS_KEY);

    const response = await fetch(url, { redirect: "manual" });

    expect(response.status).toBe(404);
    expect(await response.json()).toMatchObject({ error: { code: "open_data_not_ready" } });
  });

  it("redirects anyone, without a session, to a pre-signed URL of the file, with Cache-Control", async () => {
    storage.objects.set(OPEN_DATA_SEGMENTS_KEY, new Uint8Array([0x1f, 0x8b]));

    const response = await fetch(url, { redirect: "manual" });

    expect(response.status).toBe(302);
    const location = new URL(response.headers.get("location")!);
    expect(location.pathname).toBe(`/${OPEN_DATA_SEGMENTS_KEY}`);
    expect(Number(location.searchParams.get("X-Amz-Expires"))).toBeGreaterThanOrEqual(3600);
    expect(response.headers.get("cache-control")).toBe("public, max-age=900");
  });
});
