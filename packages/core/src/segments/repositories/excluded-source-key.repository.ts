import { Inject, Injectable } from "@nestjs/common";
import { inArray } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE, type DbExecutor } from "../../infrastructure/index.js";

/** Reads and writes on `segments.excluded_source_key` only (ADR-021 §6, ADR-039 §10). */
@Injectable()
export class ExcludedSourceKeyRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  async exclude(sourceKey: string, tx: DbExecutor = this.db): Promise<void> {
    await tx.insert(schema.excludedSourceKey).values({ sourceKey }).onConflictDoNothing();
  }

  /** The keys among `sourceKeys` an Administrator excluded. */
  async excludedAmong(sourceKeys: string[]): Promise<Set<string>> {
    if (sourceKeys.length === 0) {
      return new Set();
    }
    const rows = await this.db
      .select({ sourceKey: schema.excludedSourceKey.sourceKey })
      .from(schema.excludedSourceKey)
      .where(inArray(schema.excludedSourceKey.sourceKey, sourceKeys));
    return new Set(rows.map((row) => row.sourceKey));
  }
}
