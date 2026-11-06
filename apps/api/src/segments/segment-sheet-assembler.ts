import type { LeaderboardEntry, LeaderboardResponse, MySegmentEffort, SegmentSheet } from "@repo/contracts";
import type { LeaderboardLine, LeaderboardView, SegmentSheetView, SheetEffort } from "@repo/core/segments";
import type { AthleteIdentity } from "../identities/athlete-identities.js";

type Identity = (userId: string) => AthleteIdentity;

function toEntry(line: LeaderboardLine, identity: Identity): LeaderboardEntry {
  return {
    rank: line.rank,
    athlete: identity(line.userId),
    effortId: line.effortId,
    activityId: line.activityId,
    elapsedTimeS: line.elapsedTimeS,
    startedAt: line.startedAt.toISOString(),
  };
}

/** A Leaderboard with names and Avatars (ADR-029 §2: modules return user ids only). */
export function toLeaderboardResponse(view: LeaderboardView, identity: Identity): LeaderboardResponse {
  const legend = view.localLegend.legend;
  return {
    limited: view.limited,
    entries: view.entries.map((line) => toEntry(line, identity)),
    me: view.me ? toEntry(view.me, identity) : null,
    localLegend: {
      legend: legend ? { athlete: identity(legend.userId), effortCount: legend.effortCount } : null,
      myEffortCount: view.localLegend.myEffortCount,
    },
    athleteCount: view.athleteCount,
    nextCursor: view.nextCursor,
  };
}

function toMyEffort(effort: SheetEffort): MySegmentEffort {
  return {
    id: effort.id,
    activityId: effort.activityId,
    activityVisibility: effort.activityVisibility,
    startedAt: effort.startedAt.toISOString(),
    elapsedTimeS: effort.elapsedTimeS,
    medal: effort.medal,
    standing: effort.standing,
    isLeaderboardLine: effort.isLeaderboardLine,
    rank: effort.rank,
  };
}

export function toSegmentSheet(view: SegmentSheetView, identity: Identity): SegmentSheet {
  const leaderboard = toLeaderboardResponse(view.leaderboard, identity);
  return {
    id: view.id,
    name: view.name,
    sportTypeCode: view.sportTypeCode,
    verified: view.verified,
    distanceM: view.distanceM,
    elevationGainM: view.elevationGainM,
    avgGrade: view.avgGrade,
    maxGrade: view.maxGrade,
    climbCategory: view.climbCategory,
    track: view.track,
    starred: view.starred,
    favoriteCount: view.favoriteCount,
    isMine: view.isMine,
    canDelete: view.canDelete,
    historyMatching: view.historyMatching,
    myEfforts: view.myEfforts.map(toMyEffort),
    myRecord: view.myRecord ? toMyEffort(view.myRecord) : null,
    localLegend: leaderboard.localLegend,
    leaderboard,
  };
}
