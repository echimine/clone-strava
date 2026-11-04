import { ConflictException, Injectable, NotFoundException } from "@nestjs/common";
import { ADMIN_BATCH_MAX } from "@repo/contracts";
import { AdminFailureRepository } from "../repositories/admin-failure.repository.js";
import { RecomputeActivityUseCase } from "./recompute-activity.use-case.js";
import { ReprocessActivityImportUseCase } from "./reprocess-activity-import.use-case.js";
import { ReprocessFailedActivityUseCase } from "./reprocess-failed-activity.use-case.js";

/**
 * « Retraiter les N en échec » (ADR-038 §14): each batch loops over its unit domain action,
 * {@link ADMIN_BATCH_MAX} failures at most per click, in the order of its list. A failure that
 * changed state or vanished in the meantime (`409`, `404`) is skipped. Each returns the ids
 * relaunched.
 */
@Injectable()
export class RelaunchFailuresUseCase {
  constructor(
    private readonly failures: AdminFailureRepository,
    private readonly reprocessActivity: ReprocessFailedActivityUseCase,
    private readonly recomputeActivity: RecomputeActivityUseCase,
    private readonly reprocessImport: ReprocessActivityImportUseCase,
  ) {}

  async reprocessFailedActivities(requestId?: string): Promise<string[]> {
    const ids = await this.failures.findFailedActivityIds(ADMIN_BATCH_MAX);
    return relaunch(ids, (id) => this.reprocessActivity.execute(id, requestId));
  }

  async recomputeStaleActivities(requestId?: string): Promise<string[]> {
    const ids = await this.failures.findStaleActivityIds(ADMIN_BATCH_MAX);
    return relaunch(ids, (id) => this.recomputeActivity.execute(id, requestId));
  }

  async reprocessFailedImports(requestId?: string): Promise<string[]> {
    const ids = await this.failures.findFailedImportIds(ADMIN_BATCH_MAX);
    return relaunch(ids, (id) => this.reprocessImport.execute(id, requestId));
  }
}

/** One at a time, as the unit action would be clicked. */
async function relaunch(ids: string[], action: (id: string) => Promise<unknown>): Promise<string[]> {
  const relaunched: string[] = [];
  for (const id of ids) {
    try {
      await action(id);
      relaunched.push(id);
    } catch (error) {
      if (!(error instanceof ConflictException || error instanceof NotFoundException)) {
        throw error;
      }
    }
  }
  return relaunched;
}
