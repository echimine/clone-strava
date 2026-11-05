import { Inject, Injectable } from "@nestjs/common";
import type { Database } from "@repo/db";
import { DATABASE } from "../../infrastructure/index.js";
import { ExcludedSourceKeyRepository } from "../repositories/excluded-source-key.repository.js";
import { SegmentRepository } from "../repositories/segment.repository.js";

/**
 * An Administrator deletes a Segment (ADR-039 §10, §11; the screen is #219): final and cascading;
 * for a Nervo Segment, its source key goes to `excluded_source_key` in the same transaction, so
 * that no import ever brings it back.
 */
@Injectable()
export class DeleteSegmentAsAdministratorUseCase {
  constructor(
    @Inject(DATABASE) private readonly db: Database,
    private readonly segments: SegmentRepository,
    private readonly excludedKeys: ExcludedSourceKeyRepository,
  ) {}

  execute(segmentId: string): Promise<{ deleted: boolean; excludedSourceKey: string | null }> {
    return this.db.transaction(async (tx) => {
      const deleted = await this.segments.deleteReturningProvenance(segmentId, tx);
      if (!deleted) {
        return { deleted: false, excludedSourceKey: null };
      }
      if (deleted.origin === "nervo" && deleted.sourceKey) {
        await this.excludedKeys.exclude(deleted.sourceKey, tx);
        return { deleted: true, excludedSourceKey: deleted.sourceKey };
      }
      return { deleted: true, excludedSourceKey: null };
    });
  }
}
