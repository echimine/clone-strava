import { runMigrations } from "./migrate.js";

async function main(): Promise<void> {
  const databaseUrl = process.env.DATABASE_URL;
  if (!databaseUrl) {
    console.error("DATABASE_URL environment variable is required");
    process.exit(1);
  }

  await runMigrations(databaseUrl);
  console.log("Migrations applied successfully");
}

main().catch((error: unknown) => {
  console.error("Migration failed", error);
  process.exit(1);
});
