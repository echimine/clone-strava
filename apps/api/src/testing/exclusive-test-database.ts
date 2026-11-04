import { createDb } from "@repo/db";

/**
 * Gives one spec file a database of its own, empty and recreated at each run, for assertions on
 * global counts (the backoffice dashboard, ADR-038 §15) that other spec files running in parallel
 * would otherwise move. The database is `<TEST_DATABASE_URL's>_<suffix>`, migrated by the test
 * apps as usual.
 *
 * Must run before the test apps are imported (they read `TEST_DATABASE_URL` once):
 *
 *     await vi.hoisted(async () => {
 *       const { useExclusiveTestDatabase } = await import("../../testing/exclusive-test-database.js");
 *       await useExclusiveTestDatabase("admin_stats");
 *     });
 */
export async function useExclusiveTestDatabase(suffix: string): Promise<void> {
  const shared = new URL(process.env.TEST_DATABASE_URL ?? "postgres://strava:strava@127.0.0.1:5432/strava");
  const name = `${shared.pathname.slice(1)}_${suffix}`;
  if (!/^\w+$/.test(name)) {
    throw new Error(`Unexpected test database name ${name}`);
  }
  const { pool } = createDb(shared.toString());
  try {
    await pool.query(`drop database if exists "${name}" with (force)`);
    await pool.query(`create database "${name}"`);
  } finally {
    await pool.end();
  }
  const exclusive = new URL(shared);
  exclusive.pathname = `/${name}`;
  process.env.TEST_DATABASE_URL = exclusive.toString();
}
