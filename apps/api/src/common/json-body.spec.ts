import type { Server } from "node:http";
import express from "express";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { LOOPBACK, loopbackUrl } from "../testing/listen-on-loopback.js";
import { jsonBodyParser } from "./json-body.js";

/** ~200 kB: over express's 100 kB default, under the Itinerary limit. */
const largeBody = JSON.stringify({ padding: "x".repeat(200_000) });

/**
 * Which routes get the raised JSON body limit (ADR-030 §6): only the
 * Itinerary saves and `metrics-preview`; every other route keeps express's
 * 100 kB default.
 */
describe("jsonBodyParser", () => {
  let server: Server;
  let baseUrl: string;
  let rawBody: Buffer | undefined;

  beforeAll(async () => {
    const app = express();
    app.use(jsonBodyParser());
    app.all("/*splat", (req, res) => {
      rawBody = (req as express.Request & { rawBody?: Buffer }).rawBody;
      res.status(200).json({ bytes: JSON.stringify(req.body).length });
    });
    await new Promise<void>((resolve) => {
      server = app.listen(0, LOOPBACK, () => resolve());
    });
    baseUrl = loopbackUrl(server);
  });

  afterAll(async () => {
    await new Promise((resolve) => server.close(resolve));
  });

  function send(method: string, path: string, body = largeBody) {
    return fetch(`${baseUrl}${path}`, { method, headers: { "content-type": "application/json" }, body });
  }

  it.each([
    ["POST", "/v1/itineraries"],
    ["POST", "/v1/itineraries/metrics-preview"],
    ["PUT", "/v1/itineraries/0b7c2a52-3f0e-4bde-9a43-0d8f2c4b8e11"],
  ])("accepts a body over 100 kB on %s %s", async (method, path) => {
    expect((await send(method, path)).status).toBe(200);
  });

  it.each([
    ["POST", "/v1/activities/import"],
    ["PATCH", "/v1/itineraries/0b7c2a52-3f0e-4bde-9a43-0d8f2c4b8e11"],
    ["PUT", "/v1/me"],
    ["POST", "/v1/itineraries/metrics-preview/extra"],
  ])("keeps express's 100 kB default on %s %s", async (method, path) => {
    expect((await send(method, path)).status).toBe(413);
  });

  it("still parses a small body anywhere", async () => {
    expect((await send("PUT", "/v1/me", JSON.stringify({ name: "Ada" }))).status).toBe(200);
  });

  it("tees the raw bytes onto req.rawBody for the Resend webhook only", async () => {
    const body = JSON.stringify({ type: "email.sent" });
    await send("POST", "/v1/webhooks/resend", body);
    expect(rawBody?.toString("utf-8")).toBe(body);
    await send("POST", "/v1/itineraries", body);
    expect(rawBody).toBeUndefined();
  });
});
