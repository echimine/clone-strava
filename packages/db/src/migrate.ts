import path from "node:path";
import { drizzle } from "drizzle-orm/node-postgres";
import { migrate } from "drizzle-orm/node-postgres/migrator";
import { Pool } from "pg";

/**
 * Applies every unapplied migration in `../drizzle` (resolved relative to
 * the compiled file, so it works from `dist/` regardless of the process's
 * working directory).
 */
export async function runMigrations(databaseUrl: string): Promise<void> {
  const pool = new Pool({ connectionString: databaseUrl });
  const db = drizzle(pool);
  try {
    await migrate(db, { migrationsFolder: path.join(__dirname, "..", "drizzle") });
  } finally {
    await pool.end();
  }
}
