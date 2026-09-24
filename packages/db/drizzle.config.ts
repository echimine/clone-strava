import { defineConfig } from "drizzle-kit";

/**
 * Local dev default matches `docker-compose.dev.yml` (ADR-018). CI and
 * production always pass `DATABASE_URL` explicitly.
 */
const databaseUrl = process.env.DATABASE_URL ?? "postgresql://strava:strava@localhost:5432/strava";

export default defineConfig({
  dialect: "postgresql",
  schema: "./src/schema/index.ts",
  out: "./drizzle",
  dbCredentials: {
    url: databaseUrl,
  },
});
