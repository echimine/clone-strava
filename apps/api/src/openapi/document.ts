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
    // 3.1: nullable fields (`z.nullable()`) are `anyOf [..., null]`, which swift-openapi-generator reads (ADR-029).
    .setOpenAPIVersion("3.1.0")
    .build();
  return collapseNullableUnions(cleanupOpenApiDoc(SwaggerModule.createDocument(app, config)));
}

/**
 * Zod writes some nullable fields as `anyOf: [{ type: "integer", … }, { type: "null" }]`,
 * which swift-openapi-generator turns into a wrapper struct that cannot decode a bare value.
 * Rewrites them as the equivalent `type: ["integer", "null"]` (OpenAPI 3.1), which it maps
 * to a plain Swift optional (ADR-026, ADR-029). Unions with `$ref`s are left untouched.
 */
export function collapseNullableUnions<T>(node: T): T {
  if (Array.isArray(node)) {
    return node.map((item) => collapseNullableUnions(item)) as T;
  }
  if (typeof node !== "object" || node === null) {
    return node;
  }
  const entries = Object.entries(node).map(([key, value]) => [key, collapseNullableUnions(value)] as const);
  const schema = Object.fromEntries(entries) as Record<string, unknown>;
  const anyOf = schema.anyOf;
  if (Array.isArray(anyOf) && anyOf.length === 2) {
    const nullIndex = anyOf.findIndex((branch) => (branch as { type?: unknown }).type === "null");
    const other = anyOf[1 - nullIndex] as Record<string, unknown> | undefined;
    if (nullIndex !== -1 && other && typeof other.type === "string" && !("$ref" in other)) {
      const { anyOf: _anyOf, ...rest } = schema;
      return { ...other, ...rest, type: [other.type, "null"] } as T;
    }
  }
  return schema as T;
}
