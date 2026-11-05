import { ForbiddenException, Injectable, NotFoundException, UnprocessableEntityException } from "@nestjs/common";
import {
  LEADERBOARD_FREE_SIZE,
  LEADERBOARD_PAGE_SIZE,
  type LeaderboardFilter,
  type LeaderboardGender,
} from "@repo/contracts";
import type { ViewerExclusions } from "../../infrastructure/index.js";
import {
  decodeLeaderboardCursor,
  encodeLeaderboardCursor,
  InvalidLeaderboardCursorError,
  InvalidLeaderboardFilterError,
  leaderboardCriteria,
  requiresPremium,
  type LeaderboardCursor,
} from "../domain/leaderboard-criteria.js";
import { LeaderboardRepository, type LeaderboardLine, type LeaderboardScope } from "../repositories/leaderboard.repository.js";
import { SegmentSheetRepository } from "../repositories/segment-sheet.repository.js";

/** What `apps/api` resolved for the viewer (ADR-039 §2): `segments` reads neither `subscriptions` nor `social`. */
export interface LeaderboardReader {
  viewerId: string;
  exclusions: ViewerExclusions;
  isPremium: boolean;
  /** Accepted followees, needed only by `filter=following`. */
  followingIds: readonly string[];
}

export interface LeaderboardRequest {
  gender: LeaderboardGender;
  filter?: LeaderboardFilter;
  value?: string;
  timeZone?: string;
  cursor?: string;
}

/** The Local Legend for one sex, and the viewer's own 90-day count (ADR-039 §8). */
export interface LocalLegendView {
  legend: { userId: string; effortCount: number } | null;
  myEffortCount: number;
}

/** A Leaderboard with user ids; `apps/api` adds names and Avatars. */
export interface LeaderboardView {
  limited: boolean;
  entries: LeaderboardLine[];
  me: LeaderboardLine | null;
  localLegend: LocalLegendView;
  athleteCount: number;
  nextCursor: string | null;
}

export function segmentNotFound(): NotFoundException {
  return new NotFoundException({ code: "segment_not_found", message: "Segment not found" });
}

/**
 * `GET /v1/segments/:id/leaderboard` (ADR-039 §8, §9, §12). Without Premium, Tous only, no
 * cursor: the top 10, the viewer's line, `limited: true`; anything else is `403 premium_required`.
 * With Premium, pages of 50 on the keyset `(time, date, id)`.
 */
@Injectable()
export class GetSegmentLeaderboardUseCase {
  constructor(
    private readonly leaderboards: LeaderboardRepository,
    private readonly sheets: SegmentSheetRepository,
  ) {}

  async execute(segmentId: string, request: LeaderboardRequest, reader: LeaderboardReader): Promise<LeaderboardView> {
    if (!reader.isPremium && requiresPremium(request)) {
      throw new ForbiddenException({ code: "premium_required", message: "Premium is required for this Leaderboard" });
    }
    const scope: LeaderboardScope = {
      segmentId,
      gender: request.gender,
      criteria: this.criteria(request, reader),
      hiddenAthleteIds: reader.exclusions.hiddenAthleteIds,
    };
    const after = request.cursor === undefined ? undefined : this.decode(request.cursor);
    if (!(await this.sheets.exists(segmentId))) {
      throw segmentNotFound();
    }
    return this.read(scope, reader.viewerId, { after, limited: !reader.isPremium });
  }

  /** The sheet's preview: the top 10 of Tous and the viewer's line, Premium or not. */
  preview(segmentId: string, reader: LeaderboardReader): Promise<LeaderboardView> {
    const scope: LeaderboardScope = {
      segmentId,
      gender: "all",
      criteria: { kind: "none" },
      hiddenAthleteIds: reader.exclusions.hiddenAthleteIds,
    };
    return this.read(scope, reader.viewerId, { after: undefined, limited: true });
  }

  private async read(
    scope: LeaderboardScope,
    viewerId: string,
    options: { after: LeaderboardCursor | undefined; limited: boolean },
  ): Promise<LeaderboardView> {
    const limit = options.limited ? LEADERBOARD_FREE_SIZE : LEADERBOARD_PAGE_SIZE;
    const [rows, me, legend, myEffortCount, athleteCount] = await Promise.all([
      this.leaderboards.findPage(scope, options.after, limit + 1),
      this.leaderboards.findLineOf(scope, viewerId),
      this.leaderboards.findLocalLegend(scope.segmentId, scope.gender, scope.hiddenAthleteIds),
      this.leaderboards.countLocalLegendEfforts(scope.segmentId, viewerId),
      this.leaderboards.countAthletes(scope.segmentId),
    ]);
    const entries = rows.slice(0, limit);
    const last = entries.at(-1);
    return {
      limited: options.limited,
      entries,
      me: me ?? null,
      localLegend: { legend: legend ?? null, myEffortCount },
      athleteCount,
      nextCursor:
        !options.limited && rows.length > limit && last
          ? encodeLeaderboardCursor({ elapsedTimeS: last.elapsedTimeS, startedAt: last.cursorStartedAt, effortId: last.effortId })
          : null,
    };
  }

  private criteria(request: LeaderboardRequest, reader: LeaderboardReader) {
    try {
      return leaderboardCriteria({
        filter: request.filter,
        value: request.value,
        timeZone: request.timeZone,
        viewerId: reader.viewerId,
        followingIds: reader.followingIds,
      });
    } catch (error) {
      if (error instanceof InvalidLeaderboardFilterError) {
        throw new UnprocessableEntityException({ code: "invalid_leaderboard_filter", message: error.message });
      }
      throw error;
    }
  }

  private decode(cursor: string): LeaderboardCursor {
    try {
      return decodeLeaderboardCursor(cursor);
    } catch (error) {
      if (error instanceof InvalidLeaderboardCursorError) {
        throw new UnprocessableEntityException({ code: "invalid_cursor", message: error.message });
      }
      throw error;
    }
  }
}
