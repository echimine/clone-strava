import { randomUUID } from "node:crypto";
import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { runMigrations } from "./migrate.js";

/**
 * Integration: the migrations applied to a real PostGIS database. Uses the
 * same `TEST_DATABASE_URL` as `apps/api` and `apps/worker` (CI runs
 * `db:migrate` against it before the tests).
 */
const TEST_DATABASE_URL =
  process.env.TEST_DATABASE_URL ?? "postgres://strava:strava@127.0.0.1:5432/strava";

describe("migrations (integration)", () => {
  let pool: Pool;

  beforeAll(async () => {
    await runMigrations(TEST_DATABASE_URL);
    pool = new Pool({ connectionString: TEST_DATABASE_URL });
  });

  afterAll(async () => {
    await pool.end();
  });

  async function insertUser(): Promise<string> {
    const id = randomUUID();
    await pool.query(`insert into "user" (id, name, email) values ($1, 'Test', $2)`, [
      id,
      `migrations-${id}@example.test`,
    ]);
    return id;
  }

  it("refuses a self-follow (ADR-036 §1)", async () => {
    const userId = await insertUser();
    try {
      await expect(
        pool.query(`insert into social.follow (follower_id, followee_id) values ($1, $1)`, [userId]),
      ).rejects.toMatchObject({ code: "23514" });
    } finally {
      await pool.query(`delete from "user" where id = $1`, [userId]);
    }
  });

  it("installs `unaccent` for the accent-insensitive athlete search (ADR-036 §2)", async () => {
    const { rows } = await pool.query(`select unaccent('Éloïse Müller') as name`);
    expect(rows).toEqual([{ name: "Eloise Muller" }]);
  });

  it("still accepts a follow between two different athletes", async () => {
    const follower = await insertUser();
    const followee = await insertUser();
    try {
      await pool.query(`insert into social.follow (follower_id, followee_id) values ($1, $2)`, [
        follower,
        followee,
      ]);
      const { rows } = await pool.query(
        `select status from social.follow where follower_id = $1 and followee_id = $2`,
        [follower, followee],
      );
      expect(rows).toEqual([{ status: "pending" }]);
    } finally {
      await pool.query(`delete from "user" where id = any($1::uuid[])`, [[follower, followee]]);
    }
  });
});
