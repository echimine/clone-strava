import { Injectable } from "@nestjs/common";
import type { EditableProfile, OnboardingAnswersRequest, UpdateProfileRequest } from "@repo/contracts";
import type { ViewerExclusions } from "../infrastructure/index.js";
import { CopyGoogleAvatarUseCase, type GoogleAvatarCopy } from "./use-cases/copy-google-avatar.use-case.js";
import { GetUserSummariesUseCase } from "./use-cases/get-user-summaries.use-case.js";
import { RemoveAvatarUseCase } from "./use-cases/remove-avatar.use-case.js";
import {
  RequestAvatarUploadUseCase,
  type AvatarUpload,
} from "./use-cases/request-avatar-upload.use-case.js";
import { SearchUsersByNameUseCase } from "./use-cases/search-users-by-name.use-case.js";
import { SetAvatarUseCase } from "./use-cases/set-avatar.use-case.js";
import { SubmitOnboardingAnswersUseCase } from "./use-cases/submit-onboarding-answers.use-case.js";
import { SweepAvatarsUseCase } from "./use-cases/sweep-avatars.use-case.js";
import { UpdateProfileUseCase } from "./use-cases/update-profile.use-case.js";
import type { ActiveSportCatalog } from "./domain/active-sport-catalog.js";
import type { UserSummary } from "./domain/user-summary.js";
import { UserProfileRepository } from "./repositories/user-profile.repository.js";
import { UserSportRepository } from "./repositories/user-sport.repository.js";
import {
  DEFAULT_USER_ACTIVITY_DEFAULTS,
  type UserActivityDefaults,
} from "./domain/activity-defaults.js";

/**
 * Public facade of the `users` module (ADR-021 §1: layer 0, no dependency
 * on other domain modules). The only class other modules and apps call.
 */
@Injectable()
export class UsersService {
  constructor(
    private readonly getUserSummaries: GetUserSummariesUseCase,
    private readonly userProfiles: UserProfileRepository,
    private readonly submitOnboarding: SubmitOnboardingAnswersUseCase,
    private readonly userSports: UserSportRepository,
    private readonly searchUsersByName: SearchUsersByNameUseCase,
    private readonly requestAvatarUploadUseCase: RequestAvatarUploadUseCase,
    private readonly setAvatarUseCase: SetAvatarUseCase,
    private readonly removeAvatarUseCase: RemoveAvatarUseCase,
    private readonly sweepAvatarsUseCase: SweepAvatarsUseCase,
    private readonly copyGoogleAvatarUseCase: CopyGoogleAvatarUseCase,
    private readonly updateProfileUseCase: UpdateProfileUseCase,
  ) {}

  /**
   * Athlete search (ADR-036 §2): ids of at most 20 users whose profile name
   * contains `query` (trimmed, 2 to 50 characters, else `422 invalid_query`),
   * ignoring case and accents, word starts first, `excludeUserId` and the athletes hidden from
   * them (ADR-038 §7) left out.
   */
  searchByName(query: string | undefined, excludeUserId: string, exclusions: ViewerExclusions): Promise<string[]> {
    return this.searchUsersByName.execute(query, excludeUserId, exclusions);
  }

  /** Batch read (ADR-021 §2 rule 6), e.g. for feed authors or a profile screen. */
  getSummaries(userIds: string[]): Promise<UserSummary[]> {
    return this.getUserSummaries.execute(userIds);
  }

  /** Convenience single-id read (e.g. `GET /v1/me`), built on the batch call above. */
  async getSummary(userId: string): Promise<UserSummary | undefined> {
    const [summary] = await this.getSummaries([userId]);
    return summary;
  }

  /** The athlete's Practiced sports in their order (ADR-035 §4, ADR-036 §3); empty if never chosen. */
  getPracticedSports(userId: string): Promise<string[]> {
    return this.userSports.findCodes(userId);
  }

  /** What "Modifier le profil" shows (ADR-036 §3): every field `null` without a profile row. */
  async getEditableProfile(userId: string): Promise<EditableProfile> {
    const [profile, sports] = await Promise.all([
      this.userProfiles.findById(userId),
      this.userSports.findCodes(userId),
    ]);
    return {
      firstName: profile?.firstName ?? null,
      lastName: profile?.lastName ?? null,
      bio: profile?.bio ?? null,
      city: profile?.city ?? null,
      country: profile?.country ?? null,
      mainSportCode: sports[0] ?? null,
      birthDate: profile?.birthDate ?? null,
      gender: profile?.gender ?? null,
      weightKg: profile?.weightKg ?? null,
    };
  }

  /**
   * "Modifier le profil" (ADR-036 §3): the name everyone sees and the fields sent, already
   * trimmed and validated by the caller; `mainSportCode` becomes the first Practiced sport.
   * `422` under the minimum age or for an unknown or inactive sport (`sportCatalog`, ADR-021 §2).
   */
  updateProfile(userId: string, request: UpdateProfileRequest, sportCatalog: ActiveSportCatalog): Promise<void> {
    return this.updateProfileUseCase.execute(userId, request, sportCatalog);
  }

  /**
   * A new `avatarId` and its 15-minute pre-signed `PUT` to `avatars/{userId}/{avatarId}.jpg`, with
   * `Content-Type: image/jpeg` and `Content-Length: sizeBytes` signed (ADR-037 §2). `sizeBytes`
   * is already validated by the caller (1 byte to 1 MB).
   */
  requestAvatarUpload(userId: string, sizeBytes: number): Promise<AvatarUpload> {
    return this.requestAvatarUploadUseCase.execute(userId, sizeBytes);
  }

  /**
   * Stores the object `avatars/{userId}/{avatarId}.jpg`, already in the bucket, as the Avatar
   * (ADR-037 §2), then deletes the previous one (a failure is only logged). `409 avatar_missing`
   * when absent, `409 avatar_too_large` over 1 MB. With `onlyIfAbsent` (the Google photo copy),
   * an Avatar already set is kept and `false` is returned; the caller then owns the unused object.
   */
  setAvatar(userId: string, avatarId: string, options: { onlyIfAbsent?: boolean } = {}): Promise<boolean> {
    return this.setAvatarUseCase.execute(userId, avatarId, options);
  }

  /**
   * Called by `apps/worker`'s `copy-google-avatar` job (ADR-037 §2): the Google photo of a new
   * account becomes its Avatar, only if it has none. `PhotoUnusableError` when the photo will never
   * copy (`4xx`, too large, not an image); any other error is worth a retry.
   */
  copyGoogleAvatar(userId: string, imageUrl: string): Promise<GoogleAvatarCopy> {
    return this.copyGoogleAvatarUseCase.execute(userId, imageUrl);
  }

  /** Removes the Avatar, if any, then deletes its object (a failure is only logged, ADR-037 §2). */
  removeAvatar(userId: string): Promise<void> {
    return this.removeAvatarUseCase.execute(userId);
  }

  /**
   * Called by `apps/worker`'s daily `bucket-sweep` (ADR-037 §11): deletes the Avatars that are no
   * athlete's current `avatar_key`, once 7 days old. Returns the number of objects deleted.
   */
  sweepAvatars(): Promise<number> {
    return this.sweepAvatarsUseCase.execute();
  }

  /** Default visibility and privacy zone radius for a new activity. */
  async getActivityDefaults(userId: string): Promise<UserActivityDefaults> {
    const profile = await this.userProfiles.findById(userId);
    if (!profile) {
      return DEFAULT_USER_ACTIVITY_DEFAULTS;
    }
    return {
      defaultVisibility: profile.defaultVisibility,
      privacyZoneRadiusM: profile.privacyZoneRadiusM,
    };
  }

  /**
   * The Onboarding answers fill the empty profile fields (ADR-035 §4, §5).
   * `sportCatalog` says which sport codes are active: `users` depends on no
   * module (ADR-021 §2), so the composing app supplies it.
   */
  submitOnboardingAnswers(
    userId: string,
    answers: OnboardingAnswersRequest,
    sportCatalog: ActiveSportCatalog,
  ): Promise<void> {
    return this.submitOnboarding.execute(userId, answers, sportCatalog);
  }
}
