import { Injectable, NotFoundException } from "@nestjs/common";
import type { ActivityImport, ListActivityImportsQuery, ListActivityImportsResponse } from "@repo/contracts";
import { ActivityImportRepository } from "../repositories/activity-import.repository.js";
import { toActivityImport } from "../domain/activity-import-record.js";

/** `GET /v1/activity-imports[/:id]` (ADR-028 §3): owner-only reads. */
@Injectable()
export class GetActivityImportsUseCase {
  constructor(private readonly imports: ActivityImportRepository) {}

  async getOne(userId: string, importId: string): Promise<ActivityImport> {
    const row = await this.imports.findById(importId);
    if (!row || row.userId !== userId) {
      throw new NotFoundException({ code: "not_found", message: "Import not found" });
    }
    return toActivityImport(row);
  }

  async list(userId: string, query: ListActivityImportsQuery): Promise<ListActivityImportsResponse> {
    const { items, total } = await this.imports.listByUser(userId, query);
    return { items: items.map(toActivityImport), page: query.page, limit: query.limit, total };
  }
}
