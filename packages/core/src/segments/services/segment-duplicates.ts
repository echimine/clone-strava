import { Injectable } from "@nestjs/common";
import type { LonLat } from "@repo/geo";
import { isSameSegment } from "../domain/match-segment.js";
import { marginInDegrees } from "../domain/segment-sports.js";
import { SegmentCreationRepository } from "../repositories/segment-creation.repository.js";
import type { DbExecutor } from "../../infrastructure/index.js";

/** Both ends must lie this close to an existing Segment's for it to be a candidate duplicate. */
const DUPLICATE_ENDS_MARGIN_M = 100;

/**
 * ADR-039 §5: an existing Segment of the same sport that matches the new path **both ways**
 * (`matchSegment` of each on the other); a shorter Segment inside a longer one is allowed.
 */
@Injectable()
export class SegmentDuplicates {
  constructor(private readonly segments: SegmentCreationRepository) {}

  async find(sport: string, path: LonLat[], executor?: DbExecutor): Promise<{ id: string; name: string } | null> {
    const start = path[0]!;
    const end = path.at(-1)!;
    const margin = marginInDegrees(DUPLICATE_ENDS_MARGIN_M, [start.lat, end.lat]);
    const candidates = await this.segments.findDuplicateCandidates(sport, { start, end }, margin, executor);
    const duplicate = candidates.find((candidate) => isSameSegment(path, candidate.path));
    return duplicate ? { id: duplicate.id, name: duplicate.name } : null;
  }
}
