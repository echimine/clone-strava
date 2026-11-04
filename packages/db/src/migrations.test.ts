import { randomUUID } from "node:crypto";
import { cp, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { drizzle } from "drizzle-orm/node-postgres";
import { migrate } from "drizzle-orm/node-postgres/migrator";
import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { runMigrations } from "./migrate.js";

const MIGRATIONS_FOLDER = path.join(__dirname, "..", "drizzle");

async function insertActivity(pool: Pool, activityId: string, userId: string): Promise<void> {
  await pool.query(
    `insert into activities.activity (id, user_id, sport_type_code, title, started_at, ended_at)
     values ($1, $2, 'run', 'Run', now() - interval '1 hour', now())`,
    [activityId, userId],
  );
}

/** Applies the migrations up to `lastTag` included, from a copy of the folder with a cut journal. */
async function migrateUpTo(databaseUrl: string, lastTag: string): Promise<void> {
  const folder = await mkdtemp(path.join(tmpdir(), "migrations-"));
  try {
    await cp(MIGRATIONS_FOLDER, folder, { recursive: true });
    const journalPath = path.join(folder, "meta", "_journal.json");
    const journal = JSON.parse(await readFile(journalPath, "utf8")) as {
      entries: Array<{ tag: string }>;
    };
    const last = journal.entries.findIndex((entry) => entry.tag === lastTag);
    expect(last).toBeGreaterThanOrEqual(0);
    journal.entries = journal.entries.slice(0, last + 1);
    await writeFile(journalPath, JSON.stringify(journal));
    const pool = new Pool({ connectionString: databaseUrl });
    try {
      await migrate(drizzle(pool), { migrationsFolder: folder });
    } finally {
      await pool.end();
    }
  } finally {
    await rm(folder, { recursive: true, force: true });
  }
}

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

  it("stores Media in `activity_media`, with `media_first` and `avatar_key` (ADR-037 §12)", async () => {
    const userId = await insertUser();
    const activityId = randomUUID();
    try {
      await pool.query(`insert into users.user_profile (user_id, avatar_key) values ($1, $2)`, [
        userId,
        `avatars/${userId}/${randomUUID()}.jpg`,
      ]);
      await insertActivity(pool, activityId, userId);
      await pool.query(
        `insert into activities.activity_media (activity_id, s3_key, kind, width, height, duration_ms)
         values ($1, 'k/photo/', 'photo', 2048, 1536, null), ($1, 'k/video/', 'video', 1280, 720, 10000)`,
        [activityId],
      );
      const { rows } = await pool.query(
        `select a.media_first, m.kind::text, m.duration_ms
           from activities.activity a join activities.activity_media m on m.activity_id = a.id
          where a.id = $1 order by m.kind`,
        [activityId],
      );
      expect(rows).toEqual([
        { media_first: false, kind: "photo", duration_ms: null },
        { media_first: false, kind: "video", duration_ms: 10000 },
      ]);
    } finally {
      await pool.query(`delete from "user" where id = $1`, [userId]);
    }
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

describe("ADR-037 migration on an existing database (integration)", () => {
  const databaseName = `migrations_upgrade_${randomUUID().replaceAll("-", "")}`;
  const databaseUrl = (() => {
    const url = new URL(TEST_DATABASE_URL);
    url.pathname = `/${databaseName}`;
    return url.toString();
  })();
  let admin: Pool;

  beforeAll(async () => {
    admin = new Pool({ connectionString: TEST_DATABASE_URL });
    await admin.query(`create database "${databaseName}"`);
  });

  afterAll(async () => {
    await admin.query(`drop database if exists "${databaseName}" with (force)`);
    await admin.end();
  });

  it("keeps existing activities and profiles when renaming to Media and `avatar_key`", async () => {
    await migrateUpTo(databaseUrl, "0013_profile_follows_analysis");
    const pool = new Pool({ connectionString: databaseUrl });
    try {
      const userId = randomUUID();
      const activityId = randomUUID();
      await pool.query(`insert into "user" (id, name, email) values ($1, 'Old', $2)`, [
        userId,
        `old-${userId}@example.test`,
      ]);
      await pool.query(`insert into users.user_profile (user_id, first_name) values ($1, 'Camille')`, [
        userId,
      ]);
      await insertActivity(pool, activityId, userId);

      await runMigrations(databaseUrl);

      const { rows: activities } = await pool.query(
        `select id, media_first from activities.activity where id = $1`,
        [activityId],
      );
      expect(activities).toEqual([{ id: activityId, media_first: false }]);
      const { rows: profiles } = await pool.query(
        `select first_name, avatar_key from users.user_profile where user_id = $1`,
        [userId],
      );
      expect(profiles).toEqual([{ first_name: "Camille", avatar_key: null }]);
      const { rows: tables } = await pool.query<{ table_name: string }>(
        `select table_name from information_schema.tables where table_schema = 'activities'`,
      );
      const tableNames = tables.map((t) => t.table_name);
      expect(tableNames).toContain("activity_media");
      expect(tableNames).not.toContain("activity_attachment");
      const { rows: types } = await pool.query(
        `select t.typname from pg_type t join pg_namespace n on n.oid = t.typnamespace
          where n.nspname = 'activities' and t.typname in ('media_kind', 'attachment_kind')`,
      );
      expect(types).toEqual([{ typname: "media_kind" }]);

      // Deleting the Activity still cascades to its Media under the renamed foreign key.
      await pool.query(
        `insert into activities.activity_media (activity_id, s3_key, kind, width, height)
         values ($1, 'k/', 'photo', 10, 10)`,
        [activityId],
      );
      await pool.query(`delete from activities.activity where id = $1`, [activityId]);
      const { rows: media } = await pool.query(`select 1 from activities.activity_media`);
      expect(media).toEqual([]);
    } finally {
      await pool.end();
    }
  });
});
