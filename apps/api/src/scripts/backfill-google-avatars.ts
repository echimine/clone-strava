import "reflect-metadata";
import { NestFactory } from "@nestjs/core";
import { AuthService } from "@repo/core/auth";
import { AppModule } from "../app.module.js";

/**
 * One-off Google photo backfill (ADR-037 §2): enqueues a `copy-google-avatar` job for every
 * existing Google account with a photo; the worker copies it as the Avatar of athletes still
 * without one. Replayable without side effect. Run once after deploying, in the `api` container:
 * `node dist/scripts/backfill-google-avatars.js` (`pnpm --filter api backfill:google-avatars`
 * locally). Lives in the API because only it builds the `auth` module.
 */
async function backfillGoogleAvatars(): Promise<void> {
  const app = await NestFactory.createApplicationContext(AppModule, { logger: ["error", "warn"] });
  try {
    const enqueued = await app.get(AuthService).backfillGoogleAvatarCopies();
    console.log(`Google photo backfill: ${enqueued} copy job(s) enqueued`);
  } finally {
    await app.close();
  }
}

backfillGoogleAvatars().catch((error: unknown) => {
  console.error("Google photo backfill failed", error);
  process.exit(1);
});
