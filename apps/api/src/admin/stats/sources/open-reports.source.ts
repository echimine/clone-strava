import { Injectable } from "@nestjs/common";

/** The "Signalements ouverts" tile: open cases and when the oldest was opened. */
export interface OpenReportsCount {
  count: number;
  oldestOpenedAt: Date | null;
}

/**
 * Open Reports for the "À traiter" band (ADR-038 §10, §15).
 *
 * Placeholder: `moderation.report_case` does not exist yet (spec #210 builds it, #213 the queue),
 * and a tile whose table does not exist shows 0. #213 replaces this body with a call to the
 * moderation module (`status = 'open'`, `min(opened_at)`), and gives the tile its link.
 */
@Injectable()
export class OpenReportsSource {
  count(): Promise<OpenReportsCount> {
    return Promise.resolve({ count: 0, oldestOpenedAt: null });
  }
}
