import { Injectable } from "@nestjs/common";
import { encodePolyline } from "@repo/geo";
import { SegmentSheetRepository, type ViewerEffortRow } from "../repositories/segment-sheet.repository.js";
import {
  GetSegmentLeaderboardUseCase,
  segmentNotFound,
  type LeaderboardReader,
  type LeaderboardView,
} from "./get-segment-leaderboard.use-case.js";

/** One of the viewer's Efforts on the sheet, with the rank on the one that forms their line. */
export interface SheetEffort extends ViewerEffortRow {
  isLeaderboardLine: boolean;
  rank: number | null;
}

/** `GET /v1/segments/:id` with user ids (ADR-039 §12); `apps/api` adds names and Avatars. */
export interface SegmentSheetView {
  id: string;
  name: string;
  sportTypeCode: string;
  verified: boolean;
  distanceM: number;
  elevationGainM: number | null;
  avgGrade: number | null;
  maxGrade: number | null;
  climbCategory: "hc" | "1" | "2" | "3" | "4" | null;
  track: { polyline6: string; altitudesM: number[] };
  starred: boolean;
  favoriteCount: number;
  isMine: boolean;
  canDelete: boolean;
  historyMatching: boolean;
  myEfforts: SheetEffort[];
  myRecord: SheetEffort | null;
  /** The top 10 of Tous, the viewer's line, and the Local Legend of Tous. */
  leaderboard: LeaderboardView;
}

/** ADR-039 §8: the fastest Effort that is not rejected, the older first on a tie. */
function recordOf(efforts: SheetEffort[]): SheetEffort | null {
  let best: SheetEffort | null = null;
  for (const effort of efforts) {
    if (effort.status === "rejected") {
      continue;
    }
    if (
      !best ||
      effort.elapsedTimeS < best.elapsedTimeS ||
      (effort.elapsedTimeS === best.elapsedTimeS && effort.startedAt < best.startedAt)
    ) {
      best = effort;
    }
  }
  return best;
}

/**
 * The Segment sheet (ADR-039 §12, §15): free for everyone, `404 segment_not_found` once
 * deleted. Every Effort of the viewer whatever its visibility, newest first; the rank shows
 * only on the Effort that forms their line in Tous, after the viewer filter.
 */
@Injectable()
export class GetSegmentSheetUseCase {
  constructor(
    private readonly sheets: SegmentSheetRepository,
    private readonly leaderboard: GetSegmentLeaderboardUseCase,
  ) {}

  async execute(segmentId: string, reader: LeaderboardReader): Promise<SegmentSheetView> {
    const [segment, efforts, leaderboard] = await Promise.all([
      this.sheets.findForViewer(segmentId, reader.viewerId),
      this.sheets.findViewerEfforts(segmentId, reader.viewerId),
      this.leaderboard.preview(segmentId, reader),
    ]);
    if (!segment) {
      throw segmentNotFound();
    }
    const line = leaderboard.me;
    const myEfforts = efforts.map((effort) => {
      const isLeaderboardLine = line?.effortId === effort.id;
      return { ...effort, isLeaderboardLine, rank: isLeaderboardLine ? line!.rank : null };
    });
    const isMine = segment.createdBy !== null && segment.createdBy === reader.viewerId;
    return {
      id: segment.id,
      name: segment.name,
      sportTypeCode: segment.sportTypeCode,
      verified: segment.verified,
      distanceM: segment.distanceM ?? 0,
      elevationGainM: segment.elevationGainM,
      avgGrade: segment.avgGrade,
      maxGrade: segment.maxGrade,
      climbCategory: segment.climbCategory,
      track: {
        polyline6: encodePolyline(
          segment.coordinates.map(([lon, lat]) => ({ lon: lon!, lat: lat! })),
          6,
        ),
        altitudesM: segment.coordinates.map((point) => point[2] ?? 0),
      },
      starred: segment.starred,
      favoriteCount: segment.favoriteCount,
      isMine,
      canDelete: isMine && !segment.hasOthersEfforts,
      // A Nervo Segment has no retro-matching of its own (ADR-039 §7): no banner for it.
      historyMatching: segment.origin === "athlete" && !segment.historyMatched,
      myEfforts,
      myRecord: recordOf(myEfforts),
      leaderboard,
    };
  }
}
