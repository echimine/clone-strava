import { Injectable } from "@nestjs/common";
import type { AthleteProfileResponse } from "@repo/contracts";
import { ActivitiesService } from "@repo/core/activities";
import type { ViewerExclusions } from "@repo/core/infrastructure";
import { ItinerariesService } from "@repo/core/itineraries";
import { SocialService } from "@repo/core/social";
import { UsersService } from "@repo/core/users";
import { AthleteIdentities } from "../identities/athlete-identities.js";
import { orderPracticedSports } from "./practiced-sports.js";

/** "Abonnés que vous connaissez" on a profile header. */
const FOLLOWERS_YOU_KNOW = 2;

/**
 * `GET /v1/athletes/:id` (ADR-036 §3), composed here with one call per module: `activities`
 * computes the count, Streak and sports over what the viewer may see, `social` the follow figures,
 * `users` the Practiced sports and `itineraries` the own Itinerary count.
 */
@Injectable()
export class AthleteProfileAssembler {
  constructor(
    private readonly identities: AthleteIdentities,
    private readonly activities: ActivitiesService,
    private readonly social: SocialService,
    private readonly users: UsersService,
    private readonly itineraries: ItinerariesService,
  ) {}

  /** The caller checks that the athlete exists and is not hidden from the viewer. */
  async assemble(viewerId: string, athleteId: string, exclusions: ViewerExclusions): Promise<AthleteProfileResponse> {
    const [figures, practiced, counts, statuses, knownIds, own] = await Promise.all([
      this.activities.getAthleteProfileFigures(viewerId, athleteId),
      this.users.getPracticedSports(athleteId),
      this.social.getFollowCounts([athleteId]),
      this.social.getFollowStatuses(viewerId, [athleteId]),
      this.social.getFollowersYouKnow(viewerId, athleteId, FOLLOWERS_YOU_KNOW, exclusions),
      viewerId === athleteId ? this.ownFields(athleteId) : undefined,
    ]);
    const identity = await this.identities.resolve([athleteId, ...knownIds]);
    const followCounts = counts.get(athleteId);

    return {
      athlete: identity(athleteId),
      activityCount: figures.activityCount,
      streakWeeks: figures.streakWeeks,
      followerCount: followCounts?.followerCount ?? 0,
      followingCount: followCounts?.followingCount ?? 0,
      viewerFollowStatus: statuses.get(athleteId) ?? null,
      followersYouKnow: knownIds.map((id) => identity(id)),
      practicedSports: orderPracticedSports(practiced, figures.sportActivityCounts),
      ...own,
    };
  }

  private async ownFields(userId: string) {
    const [settings, pendingFollowRequestCount, itineraryCount] = await Promise.all([
      this.social.getFollowSettings(userId),
      this.social.countFollowRequests(userId),
      this.itineraries.countByOwner(userId),
    ]);
    return { approveFollowers: settings.approveFollowers, pendingFollowRequestCount, itineraryCount };
  }
}
