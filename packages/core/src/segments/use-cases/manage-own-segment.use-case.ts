import { ConflictException, ForbiddenException, Injectable, NotFoundException } from "@nestjs/common";
import { SegmentCreationRepository } from "../repositories/segment-creation.repository.js";

/**
 * What the creator of a Segment may do after creating it (ADR-039 §5, §11): rename it at any
 * time, never its path; delete it while nobody else has an Effort on it. A Segment without a
 * creator (Nervo, or the creator's account deleted) is left to the Administrators.
 */
@Injectable()
export class ManageOwnSegmentUseCase {
  constructor(private readonly segments: SegmentCreationRepository) {}

  /** `404 segment_not_found`, `403 not_creator`; a verified Segment stays verified. */
  async rename(userId: string, segmentId: string, name: string): Promise<{ id: string; name: string }> {
    await this.assertCreator(userId, segmentId);
    await this.segments.rename(segmentId, name);
    return { id: segmentId, name };
  }

  /**
   * Final, cascading (Efforts, favourites, verdicts); a running retro-matching stops at its next
   * page. `409 has_other_efforts` once another athlete has an Effort on it.
   */
  async delete(userId: string, segmentId: string): Promise<void> {
    await this.assertCreator(userId, segmentId);
    if (!(await this.segments.deleteUnlessOthersHaveEfforts(segmentId, userId))) {
      throw new ConflictException({
        code: "has_other_efforts",
        message: "Another athlete has an Effort on this Segment",
      });
    }
  }

  private async assertCreator(userId: string, segmentId: string): Promise<void> {
    const segment = await this.segments.findCreator(segmentId);
    if (!segment) {
      throw new NotFoundException({ code: "segment_not_found", message: "Segment not found" });
    }
    if (segment.createdBy !== userId) {
      throw new ForbiddenException({ code: "not_creator", message: "Only the creator may change this Segment" });
    }
  }
}
