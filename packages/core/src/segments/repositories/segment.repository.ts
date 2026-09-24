import { Inject, Injectable, NotImplementedException } from "@nestjs/common";
import { type Database } from "@repo/db";
import { DATABASE } from "../../infrastructure/index.js";

/** Reads on `segments.segment` only (ADR-021 §6); writes come from later admin tooling. */
@Injectable()
export class SegmentRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  /** GiST proximity search (ADR-019 §8): candidate segments near a route. */
  findCandidatesNearRoute(_sportTypeCode: string, _routeWkt: string): Promise<unknown[]> {
    throw new NotImplementedException();
  }
}
