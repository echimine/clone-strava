import { Inject, Injectable } from "@nestjs/common";
import { asc, eq } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE } from "../../infrastructure/index.js";

/** Reads on `sports.sport_type` only (ADR-021 §6); the table is populated by migration. */
@Injectable()
export class SportTypeRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  findByCode(code: string) {
    return this.db.query.sportType.findFirst({ where: eq(schema.sportType.code, code) });
  }

  listActive() {
    return this.db.query.sportType.findMany({
      where: eq(schema.sportType.isActive, true),
      orderBy: [asc(schema.sportType.displayOrder)],
    });
  }
}
