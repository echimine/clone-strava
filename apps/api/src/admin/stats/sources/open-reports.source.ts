import { Injectable } from "@nestjs/common";
import { ModerationService } from "@repo/core/moderation";

/** The "Signalements ouverts" tile: open cases and when the oldest was opened. */
export interface OpenReportsCount {
  count: number;
  oldestOpenedAt: Date | null;
}

/** Open report cases for the "À traiter" band (ADR-038 §10, §15), read in the moderation queue. */
@Injectable()
export class OpenReportsSource {
  constructor(private readonly moderation: ModerationService) {}

  count(excludedUserIds: readonly string[]): Promise<OpenReportsCount> {
    return this.moderation.countOpenCases(excludedUserIds);
  }
}
