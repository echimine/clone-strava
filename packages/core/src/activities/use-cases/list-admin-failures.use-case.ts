import { Injectable } from "@nestjs/common";
import type { FailedActivityRow, FailedImportRow, FailurePage, StaleActivityRow } from "../domain/admin-failure.js";
import { AdminFailureRepository } from "../repositories/admin-failure.repository.js";

type Page = { page: number; pageSize: number };

/** The three lists of the Jobs screen's "Échecs" tab (ADR-038 §14), newest first. */
@Injectable()
export class ListAdminFailuresUseCase {
  constructor(private readonly failures: AdminFailureRepository) {}

  activities(page: Page): Promise<FailurePage<FailedActivityRow>> {
    return this.failures.findFailedActivities(page);
  }

  imports(page: Page): Promise<FailurePage<FailedImportRow>> {
    return this.failures.findFailedImports(page);
  }

  recomputes(page: Page): Promise<FailurePage<StaleActivityRow>> {
    return this.failures.findStaleActivities(page);
  }
}
