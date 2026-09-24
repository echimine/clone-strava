import { Inject, Injectable, NotImplementedException } from "@nestjs/common";
import { type Database } from "@repo/db";
import { DATABASE } from "../../infrastructure/index.js";

/** Reads and writes on `engagement.comment` only (ADR-021 §6). */
@Injectable()
export class CommentRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  countByActivityIds(_activityIds: string[]): Promise<Map<string, number>> {
    throw new NotImplementedException();
  }

  async add(_userId: string, _activityId: string, _body: string): Promise<void> {
    throw new NotImplementedException();
  }
}
