import "reflect-metadata";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { NestFactory } from "@nestjs/core";
import { AppModule } from "../app.module.js";
import { applyGlobalPrefix, createOpenApiDocument } from "./document.js";

/**
 * Writes the OpenAPI spec to the file the mobile app's swift-openapi-generator
 * plugin reads (ADR-026), without listening or running migrations.
 * `pnpm mobile:sync-openapi` runs it; CI re-runs it and fails on any diff.
 */
const OUTPUT = resolve(__dirname, "../../../mobile/StravaClone/Core/Network/OpenAPI/openapi.json");

async function exportOpenApi(): Promise<void> {
  // `preview`: build the module graph without instantiating providers, so no
  // database/Redis connection is opened just to read route metadata.
  const app = await NestFactory.create(AppModule, { preview: true, logger: false });
  applyGlobalPrefix(app);
  const document = createOpenApiDocument(app);
  mkdirSync(dirname(OUTPUT), { recursive: true });
  // Stable formatting + trailing newline: re-running on an unchanged API must
  // produce a byte-identical file (the CI drift check relies on it).
  writeFileSync(OUTPUT, `${JSON.stringify(document, null, 2)}\n`);
  await app.close();
  console.log(`OpenAPI spec written to ${OUTPUT} (${Object.keys(document.paths).length} paths)`);
}

exportOpenApi().catch((error: unknown) => {
  console.error("Failed to export the OpenAPI spec", error);
  process.exit(1);
});
