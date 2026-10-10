import express from "express";

/**
 * Max JSON body of an Itinerary save or `metrics-preview`. Express's 100 kB
 * default is too small for an Itinerary body: up to 50,000 polyline6 points
 * across its Legs (ADR-030 §6). Every other route keeps the default.
 */
export const ITINERARY_JSON_BODY_LIMIT = "1mb";

/** `POST /v1/itineraries`, `POST /v1/itineraries/metrics-preview`, `PUT /v1/itineraries/:id`. */
function carriesItineraryGeometry(method: string, path: string): boolean {
  if (method === "POST") return path === "/v1/itineraries" || path === "/v1/itineraries/metrics-preview";
  return method === "PUT" && /^\/v1\/itineraries\/[^/]+$/.test(path);
}

/**
 * The app's single JSON body parser: the raised limit on the routes that
 * carry an Itinerary's geometry, express's default everywhere else.
 *
 * `verify` always receives the pre-parse buffer, for every route; teeing it
 * onto `req.rawBody` for the Resend webhook alone gives
 * `ResendWebhookController` byte-exact bytes for its Svix HMAC check
 * (ADR-023) without a second raw-body-only middleware/route.
 */
export function jsonBodyParser(): express.RequestHandler {
  const options = {
    // `verify` types `req` as the bare `http.IncomingMessage` (body-parser
    // has no express dependency); `originalUrl`/`rawBody` are express-only,
    // hence the single cast for both reads/writes.
    verify: (req: unknown, _res: unknown, buf: Buffer) => {
      const request = req as express.Request & { rawBody?: Buffer };
      if (request.originalUrl === "/v1/webhooks/resend") {
        request.rawBody = buf;
      }
    },
  };
  const itineraryJson = express.json({ ...options, limit: ITINERARY_JSON_BODY_LIMIT });
  const defaultJson = express.json(options);
  return (req, res, next) =>
    (carriesItineraryGeometry(req.method, req.path) ? itineraryJson : defaultJson)(req, res, next);
}
