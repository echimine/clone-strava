import { Injectable } from "@nestjs/common";
import type { MatchSegmentsJob } from "@repo/contracts";
import { MatchSegmentsUseCase } from "./use-cases/match-segments.use-case.js";

/**
 * Public facade of the `segments` module (ADR-021 §1: layer 3, may depend
 * on `activities`, `sports`).
 */
@Injectable()
export class SegmentsService {
  constructor(private readonly matchSegmentsUseCase: MatchSegmentsUseCase) {}

  /** Called by `apps/worker`'s `match-segments` processor (ADR-011 §1). */
  matchSegments(job: MatchSegmentsJob): Promise<void> {
    return this.matchSegmentsUseCase.execute(job);
  }
}
