import { RequestMethod } from "@nestjs/common";
import type { INestApplication } from "@nestjs/common";
import { DocumentBuilder, SwaggerModule, type OpenAPIObject } from "@nestjs/swagger";
import { cleanupOpenApiDoc } from "nestjs-zod";

/**
 * Versioned routes (ADR-009 §8), excluding `/health` (ADR-018 §6, public,
 * outside rate limiting and authentication) and the Better Auth mount.
 * Shared by `main.ts` and the OpenAPI export (ADR-026) so the exported spec
 * carries exactly the paths the server serves.
 */
export function applyGlobalPrefix(app: INestApplication): void {
  app.setGlobalPrefix("v1", {
    exclude: [
      { path: "health", method: RequestMethod.GET },
      { path: "api/auth/*path", method: RequestMethod.ALL },
    ],
  });
}

/**
 * OpenAPI, generated from the same Zod schemas used to validate requests
 * (ADR-009 §"api stack" "Documentation"). Source of the Swift models the
 * mobile app generates at build time (ADR-005, ADR-026).
 */
export function createOpenApiDocument(app: INestApplication): OpenAPIObject {
  const config = new DocumentBuilder()
    .setTitle("Clone Strava API")
    .setDescription("REST API for the mobile app and the backoffice (ADR-009).")
    .setVersion("1")
    .build();
  return cleanupOpenApiDoc(SwaggerModule.createDocument(app, config));
}
