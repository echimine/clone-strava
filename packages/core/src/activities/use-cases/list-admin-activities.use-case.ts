import { Injectable } from "@nestjs/common";
import type { AdminActivityFilter, AdminActivityRow } from "../domain/admin-activity.js";
import { AdminActivityRepository } from "../repositories/admin-activity.repository.js";

/**
 * `GET /v1/admin/activities` (ADR-038 §11): every Activity, private ones included, newest created
 * first; search over the title and the author's name or e-mail.
 */
@Injectable()
export class ListAdminActivitiesUseCase {
  constructor(private readonly adminActivities: AdminActivityRepository) {}

  execute(
    filter: AdminActivityFilter,
    page: { page: number; pageSize: number },
  ): Promise<{ rows: AdminActivityRow[]; total: number }> {
    return this.adminActivities.findPage(filter, page);
  }
}
