import "reflect-metadata";
import { createReadStream, existsSync } from "node:fs";
import { resolve } from "node:path";
import { createInterface } from "node:readline";
import { createGunzip } from "node:zlib";
import { NestFactory } from "@nestjs/core";
import { SegmentsService } from "@repo/core/segments";
import { AppModule } from "../app.module.js";

/**
 * `pnpm segments:import <file.ndjson[.gz]>` (ADR-039 §10): loads the Nervo generator's output into
 * the database `DATABASE_URL` points at (the target, over an SSH tunnel), then enqueues the
 * per-Activity replay of `match-segments` on `REDIS_URL`'s queue. Never from the backoffice.
 * Replayable: a run only adds Segments, and prints what it did.
 */
async function importNervoSegments(): Promise<void> {
  const argument = process.argv[2];
  if (!argument) {
    console.error("Usage : pnpm segments:import <segments.ndjson[.gz]>");
    process.exit(2);
  }
  // `pnpm --filter api` runs here; the operator typed the path where they were.
  const path = resolve(process.env.INIT_CWD ?? process.cwd(), argument);
  if (!existsSync(path)) {
    console.error(`Fichier introuvable : ${path}`);
    process.exit(2);
  }
  const app = await NestFactory.createApplicationContext(AppModule, { logger: ["error", "warn"] });
  try {
    const input = createReadStream(path);
    const lines = createInterface({ input: path.endsWith(".gz") ? input.pipe(createGunzip()) : input, crlfDelay: Infinity });
    const report = await app.get(SegmentsService).importNervoSegments(lines);
    console.log(
      [
        `Import Nervo ${report.importId} :`,
        `  insérés          ${report.inserted}`,
        `  déjà présents    ${report.alreadyPresent}`,
        `  exclus           ${report.excluded}`,
        `  doublons         ${report.duplicates}`,
        `  lignes invalides ${report.invalid.length}`,
        `  Activités enfilées pour l'appariement ${report.activitiesEnqueued}`,
        ...report.invalid.slice(0, 20).map(({ line, reason }) => `  ligne ${line} : ${reason}`),
      ].join("\n"),
    );
  } finally {
    await app.close();
  }
}

importNervoSegments().catch((error: unknown) => {
  console.error("Nervo import failed", error);
  process.exit(1);
});
