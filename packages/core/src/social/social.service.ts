import { Injectable } from "@nestjs/common";
import type { FollowListKind, FollowListPage } from "./domain/follow-list.js";
import type { FollowCounts, FollowRelation, FollowState } from "./domain/follow-state.js";
import { FollowSettingsRepository } from "./repositories/follow-settings.repository.js";
import { FollowRepository } from "./repositories/follow.repository.js";
import { FollowStatusesReader } from "./services/follow-statuses-reader.js";
import { AcceptFollowRequestUseCase } from "./use-cases/accept-follow-request.use-case.js";
import { FollowAthleteUseCase } from "./use-cases/follow-athlete.use-case.js";
import { GetFolloweeIdsUseCase } from "./use-cases/get-followee-ids.use-case.js";
import { ListFollowsUseCase } from "./use-cases/list-follows.use-case.js";
import { RefuseFollowRequestUseCase } from "./use-cases/refuse-follow-request.use-case.js";
import { RemoveFollowerUseCase } from "./use-cases/remove-follower.use-case.js";
import { UnfollowAthleteUseCase } from "./use-cases/unfollow-athlete.use-case.js";
import { UpdateFollowSettingsUseCase } from "./use-cases/update-follow-settings.use-case.js";

type PageQuery = { cursor?: string; limit: number };

/**
 * Public facade of the `social` module (ADR-021 §1: layer 1, may depend on
 * `users`), ADR-036 §1. Athletes are ids only; the callers check that an
 * athlete exists (`public.user` belongs to `auth`) and assemble identities.
 */
@Injectable()
export class SocialService {
  constructor(
    private readonly followAthlete: FollowAthleteUseCase,
    private readonly unfollowAthlete: UnfollowAthleteUseCase,
    private readonly listFollowsUseCase: ListFollowsUseCase,
    private readonly acceptFollowRequest: AcceptFollowRequestUseCase,
    private readonly refuseFollowRequest: RefuseFollowRequestUseCase,
    private readonly removeFollowerUseCase: RemoveFollowerUseCase,
    private readonly updateFollowSettingsUseCase: UpdateFollowSettingsUseCase,
    private readonly getFolloweeIdsUseCase: GetFolloweeIdsUseCase,
    private readonly statuses: FollowStatusesReader,
    private readonly follows: FollowRepository,
    private readonly settings: FollowSettingsRepository,
  ) {}

  /** `accepted`, or `pending` when the athlete approves followers. Idempotent; self is `422 cannot_follow_self`. */
  follow(followerId: string, followeeId: string): Promise<FollowState> {
    return this.followAthlete.execute(followerId, followeeId);
  }

  /** Unfollow or cancel a pending request. Idempotent. */
  unfollow(followerId: string, followeeId: string): Promise<FollowState> {
    return this.unfollowAthlete.execute(followerId, followeeId);
  }

  /** An athlete's accepted followers or followees, most recent first, with the viewer's relation to each. */
  listFollows(viewerId: string, athleteId: string, kind: FollowListKind, query: PageQuery): Promise<FollowListPage> {
    return this.listFollowsUseCase.execute(viewerId, athleteId, kind, query);
  }

  /** The viewer's incoming pending requests, most recent first; `since` is when each was made. */
  listFollowRequests(userId: string, query: PageQuery): Promise<FollowListPage> {
    return this.listFollowsUseCase.execute(userId, userId, "requests", query);
  }

  /** `404 follow_request_not_found` without a pending request from `followerId`. */
  acceptRequest(userId: string, followerId: string): Promise<void> {
    return this.acceptFollowRequest.execute(userId, followerId);
  }

  /** Idempotent. */
  refuseRequest(userId: string, followerId: string): Promise<void> {
    return this.refuseFollowRequest.execute(userId, followerId);
  }

  /** Idempotent. */
  removeFollower(userId: string, followerId: string): Promise<void> {
    return this.removeFollowerUseCase.execute(userId, followerId);
  }

  /** "Approuver mes abonnés"; `false` until set. */
  async getFollowSettings(userId: string): Promise<{ approveFollowers: boolean }> {
    return { approveFollowers: await this.settings.approvesFollowers(userId) };
  }

  /** Turning approval off accepts every pending request, in the same transaction. */
  updateFollowSettings(userId: string, approveFollowers: boolean): Promise<{ approveFollowers: boolean }> {
    return this.updateFollowSettingsUseCase.execute(userId, approveFollowers);
  }

  /**
   * Batch read for every list that shows a follow button (ADR-036 §1):
   * each of `athleteIds` maps to the viewer's relation, `null` for the viewer.
   */
  getFollowStatuses(viewerId: string, athleteIds: string[]): Promise<Map<string, FollowRelation | null>> {
    return this.statuses.read(viewerId, athleteIds);
  }

  /** Batch read (ADR-036 §1, §3): accepted followers and followees of each athlete, zero included. */
  async getFollowCounts(athleteIds: string[]): Promise<Map<string, FollowCounts>> {
    const [followers, following] = await Promise.all([
      this.follows.countFollowers(athleteIds),
      this.follows.countFollowing(athleteIds),
    ]);
    return new Map(
      athleteIds.map((id) => [id, { followerCount: followers.get(id) ?? 0, followingCount: following.get(id) ?? 0 }]),
    );
  }

  /** Batch read (ADR-021 §2 rule 6, §6): the feed's first step. */
  getFolloweeIds(userId: string): Promise<string[]> {
    return this.getFolloweeIdsUseCase.execute(userId);
  }
}
