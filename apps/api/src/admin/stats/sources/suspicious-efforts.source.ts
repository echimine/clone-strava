import { Injectable } from "@nestjs/common";

/**
 * Efforts to review for the "À traiter" band (ADR-038 §15, §16).
 *
 * Placeholder: `segment_effort.status` does not exist yet (spec #219), and a tile whose table
 * does not exist shows 0. #219 replaces this body with a call to the segments module
 * (`status = 'suspicious'`), and gives the tile its link.
 */
@Injectable()
export class SuspiciousEffortsSource {
  count(): Promise<number> {
    return Promise.resolve(0);
  }
}
