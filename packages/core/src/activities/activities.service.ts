import { Injectable } from "@nestjs/common";
import type { InstantRange } from "../infrastructure/index.js";
import type { ActivityFailureCounts, ActivityGrowthCounts } from "./domain/activity-admin-stats.js";
import { ActivityAdminStatsRepository } from "./repositories/activity-admin-stats.repository.js";
import type {
  ActivityImport,
  AthleteStatsResponse,
  ConfirmMediaRequest,
  CreateActivityImportRequest,
  CreateActivityRequest,
  UpdateActivityRequest,
  ImportActivityJob,
  ListActivityImportsQuery,
  ListActivityImportsResponse,
  MediaUploadUrlsRequest,
  MediaUploadUrlsResponse,
  ProcessActivityJob,
  ProgressResponse,
  ReprocessActivityJob,
  UploadUrlResponse,
} from "@repo/contracts";
import type { ViewerExclusions } from "../infrastructure/index.js";
import { CreateActivityUseCase, type CreateActivityResult } from "./use-cases/create-activity.use-case.js";
import { RequestUploadUrlUseCase } from "./use-cases/request-upload-url.use-case.js";
import { CompleteActivityUseCase } from "./use-cases/complete-activity.use-case.js";
import { ProcessActivityUseCase } from "./use-cases/process-activity.use-case.js";
import { ReconcileStuckActivitiesUseCase } from "./use-cases/reconcile-stuck-activities.use-case.js";
import { GetActivitiesUseCase } from "./use-cases/get-activities.use-case.js";
import { GetActivityMediaUseCase } from "./use-cases/get-activity-media.use-case.js";
import {
  CreateActivityImportUseCase,
  type CreateActivityImportResult,
} from "./use-cases/create-activity-import.use-case.js";
import { RequestImportUploadUrlUseCase } from "./use-cases/request-import-upload-url.use-case.js";
import { CompleteActivityImportUseCase } from "./use-cases/complete-activity-import.use-case.js";
import { GetActivityImportsUseCase } from "./use-cases/get-activity-imports.use-case.js";
import {
  ImportActivityFromFileUseCase,
  type ImportActivityResult,
} from "./use-cases/import-activity-from-file.use-case.js";
import { ReprocessActivityImportUseCase } from "./use-cases/reprocess-activity-import.use-case.js";
import { GetFeedPageUseCase } from "./use-cases/get-feed-page.use-case.js";
import { GetVisibleActivityUseCase } from "./use-cases/get-visible-activity.use-case.js";
import { GetActivityDetailUseCase } from "./use-cases/get-activity-detail.use-case.js";
import { DeleteActivityUseCase } from "./use-cases/delete-activity.use-case.js";
import { UpdateActivityUseCase } from "./use-cases/update-activity.use-case.js";
import { ReprocessActivityUseCase } from "./use-cases/reprocess-activity.use-case.js";
import { GetProgressUseCase } from "./use-cases/get-progress.use-case.js";
import { GetAthleteStatsUseCase } from "./use-cases/get-athlete-stats.use-case.js";
import {
  GetAthleteProfileFiguresUseCase,
  type AthleteProfileFigures,
} from "./use-cases/get-athlete-profile-figures.use-case.js";
import { GetAthleteActivitiesPageUseCase } from "./use-cases/get-athlete-activities-page.use-case.js";
import { GetAthleteGalleryPageUseCase } from "./use-cases/get-athlete-gallery-page.use-case.js";
import { SweepBucketUseCase } from "./use-cases/sweep-bucket.use-case.js";
import { RequestMediaUploadUrlsUseCase } from "./use-cases/request-media-upload-urls.use-case.js";
import { ConfirmMediaUseCase, type ConfirmMediaResult } from "./use-cases/confirm-media.use-case.js";
import { DeleteMediaUseCase } from "./use-cases/delete-media.use-case.js";
import { ListAdminActivitiesUseCase } from "./use-cases/list-admin-activities.use-case.js";
import { GetAdminActivityUseCase } from "./use-cases/get-admin-activity.use-case.js";
import { ReprocessFailedActivityUseCase } from "./use-cases/reprocess-failed-activity.use-case.js";
import { DeleteActivityAsSanctionUseCase } from "./use-cases/delete-activity-as-sanction.use-case.js";
import { RemoveMediaAsSanctionUseCase } from "./use-cases/remove-media-as-sanction.use-case.js";
import { ResetActivityTextUseCase, type ActivityTextReset } from "./use-cases/reset-activity-text.use-case.js";
import { AdminActivityRepository } from "./repositories/admin-activity.repository.js";
import type {
  ActivityLabel,
  AdminActivityFilter,
  AdminActivityRecord,
  AdminActivityRow,
} from "./domain/admin-activity.js";
import type { ActivityDetailRecord } from "./domain/activity-detail.js";
import type { ActivityMediaRecord, GalleryMediaPage } from "./domain/activity-media.js";
import type { ActivityRecord } from "./domain/activity-record.js";
import type { FeedActivityPage } from "./domain/feed-activity.js";

/**
 * Public facade of the `activities` module (ADR-021 §1: layer 2, may
 * depend on `sports`, `users`, `social`). The largest module (upload,
 * processing, feed).
 */
@Injectable()
export class ActivitiesService {
  constructor(
    private readonly adminStats: ActivityAdminStatsRepository,
    private readonly createActivityUseCase: CreateActivityUseCase,
    private readonly requestUploadUrlUseCase: RequestUploadUrlUseCase,
    private readonly completeActivityUseCase: CompleteActivityUseCase,
    private readonly processActivityUseCase: ProcessActivityUseCase,
    private readonly reconcileStuckActivitiesUseCase: ReconcileStuckActivitiesUseCase,
    private readonly getActivitiesUseCase: GetActivitiesUseCase,
    private readonly getActivityMediaUseCase: GetActivityMediaUseCase,
    private readonly createActivityImportUseCase: CreateActivityImportUseCase,
    private readonly requestImportUploadUrlUseCase: RequestImportUploadUrlUseCase,
    private readonly completeActivityImportUseCase: CompleteActivityImportUseCase,
    private readonly getActivityImportsUseCase: GetActivityImportsUseCase,
    private readonly importActivityFromFileUseCase: ImportActivityFromFileUseCase,
    private readonly reprocessActivityImportUseCase: ReprocessActivityImportUseCase,
    private readonly getFeedPageUseCase: GetFeedPageUseCase,
    private readonly getVisibleActivityUseCase: GetVisibleActivityUseCase,
    private readonly getActivityDetailUseCase: GetActivityDetailUseCase,
    private readonly deleteActivityUseCase: DeleteActivityUseCase,
    private readonly updateActivityUseCase: UpdateActivityUseCase,
    private readonly reprocessActivityUseCase: ReprocessActivityUseCase,
    private readonly getProgressUseCase: GetProgressUseCase,
    private readonly getAthleteStatsUseCase: GetAthleteStatsUseCase,
    private readonly getAthleteProfileFiguresUseCase: GetAthleteProfileFiguresUseCase,
    private readonly getAthleteActivitiesPageUseCase: GetAthleteActivitiesPageUseCase,
    private readonly getAthleteGalleryPageUseCase: GetAthleteGalleryPageUseCase,
    private readonly sweepBucketUseCase: SweepBucketUseCase,
    private readonly requestMediaUploadUrlsUseCase: RequestMediaUploadUrlsUseCase,
    private readonly confirmMediaUseCase: ConfirmMediaUseCase,
    private readonly deleteMediaUseCase: DeleteMediaUseCase,
    private readonly listAdminActivitiesUseCase: ListAdminActivitiesUseCase,
    private readonly getAdminActivityUseCase: GetAdminActivityUseCase,
    private readonly reprocessFailedActivityUseCase: ReprocessFailedActivityUseCase,
    private readonly deleteActivityAsSanctionUseCase: DeleteActivityAsSanctionUseCase,
    private readonly removeMediaAsSanctionUseCase: RemoveMediaAsSanctionUseCase,
    private readonly resetActivityTextUseCase: ResetActivityTextUseCase,
    private readonly adminActivities: AdminActivityRepository,
  ) {}

  /** Backoffice dashboard, "À traiter" (ADR-038 §15): failed Activities and recent failed imports. */
  getAdminFailureCounts(failedImportsSince: Date): Promise<ActivityFailureCounts> {
    return this.adminStats.countFailures(failedImportsSince);
  }

  /** Backoffice dashboard, "Croissance" (ADR-038 §15): Activities started, active athletes, Media. */
  getAdminGrowthCounts(range: InstantRange, excludedUserIds: readonly string[]): Promise<ActivityGrowthCounts> {
    return this.adminStats.countGrowth(range, excludedUserIds);
  }

  /** Backoffice dashboard chart (ADR-038 §15): Activities started per Paris day. */
  countActivitiesPerParisDay(range: InstantRange, excludedUserIds: readonly string[]): Promise<Map<string, number>> {
    return this.adminStats.countStartedPerParisDay(range, excludedUserIds);
  }

  create(userId: string, request: CreateActivityRequest): Promise<CreateActivityResult> {
    return this.createActivityUseCase.execute(userId, request);
  }

  requestUploadUrl(userId: string, activityId: string) {
    return this.requestUploadUrlUseCase.execute(userId, activityId);
  }

  complete(userId: string, activityId: string, requestId?: string): Promise<ActivityRecord> {
    return this.completeActivityUseCase.execute(userId, activityId, requestId);
  }

  /** Called by `apps/worker`'s `process-activity` processor (ADR-011 §1). */
  process(job: ProcessActivityJob): Promise<void> {
    return this.processActivityUseCase.execute(job);
  }

  /** Last technical attempt of `process-activity` failed (ADR-019 §6). */
  markProcessingFailed(job: ProcessActivityJob): Promise<void> {
    return this.processActivityUseCase.markTechnicalFailure(job);
  }

  /** Called by `apps/worker`'s `reprocess-activity` processor after a sport change (ADR-033 §5). */
  reprocess(job: ReprocessActivityJob): Promise<void> {
    return this.reprocessActivityUseCase.execute(job);
  }

  /** Called by `apps/worker`'s reconciliation schedule (ADR-019 §7). */
  reconcileStuck(): Promise<number> {
    return this.reconcileStuckActivitiesUseCase.execute();
  }

  /**
   * Called by `apps/worker`'s daily `bucket-sweep` (ADR-037 §11): deletes the Activity, Media and
   * import folders that no row references, once 7 days old. Returns the number of objects deleted.
   */
  sweepBucket(): Promise<number> {
    return this.sweepBucketUseCase.execute();
  }

  /** Batch read (ADR-021 §2 rule 6): used by `engagement`, `segments` and list screens. */
  getMany(ids: string[]): Promise<ActivityRecord[]> {
    return this.getActivitiesUseCase.execute(ids);
  }

  /**
   * The Media of these Activities in one batch read, in order (ADR-037 §7), `[]` for an Activity
   * without any. The caller passes only Activities the viewer may see, then signs the files.
   */
  getMedia(activityIds: string[]): Promise<Map<string, ActivityMediaRecord[]>> {
    return this.getActivityMediaUseCase.execute(activityIds);
  }

  // Every read on a viewer's behalf takes the viewer filter (ADR-038 §7): hidden authors and
  // reported activities are left out, as if they did not exist.

  /** Feed steps 1-2 (ADR-021 §6, ADR-029): the caller adds authors and engagement. */
  getFeedPage(
    viewerId: string,
    query: { cursor?: string; limit: number },
    exclusions: ViewerExclusions,
  ): Promise<FeedActivityPage> {
    return this.getFeedPageUseCase.execute(viewerId, query, exclusions);
  }

  /**
   * An athlete's processed Activities that `viewerId` may see, as a feed page (ADR-036 §3). The
   * caller checks the athlete exists and is not hidden, then adds authors and engagement.
   */
  getAthleteActivitiesPage(
    viewerId: string,
    athleteId: string,
    query: { cursor?: string; limit: number },
    exclusions: ViewerExclusions,
  ): Promise<FeedActivityPage> {
    return this.getAthleteActivitiesPageUseCase.execute(viewerId, athleteId, query, exclusions);
  }

  /**
   * The Media of an athlete's processed Activities that `viewerId` may see, as a Gallery page
   * (ADR-037 §9). The caller checks the athlete exists and is not hidden, and signs the files.
   */
  getAthleteGalleryPage(
    viewerId: string,
    athleteId: string,
    query: { cursor?: string; limit: number },
    exclusions: ViewerExclusions,
  ): Promise<GalleryMediaPage> {
    return this.getAthleteGalleryPageUseCase.execute(viewerId, athleteId, query, exclusions);
  }

  /** The activity if `viewerId` may see it, `null` otherwise (ADR-029). */
  getVisible(viewerId: string, activityId: string, exclusions: ViewerExclusions): Promise<ActivityRecord | null> {
    return this.getVisibleActivityUseCase.execute(viewerId, activityId, exclusions);
  }

  /**
   * The detail of an activity `viewerId` may see (ADR-033 §2): the author's in any state, others'
   * once processed; `404 activity_not_found` otherwise. The caller adds author and engagement.
   */
  getDetail(viewerId: string, activityId: string, exclusions: ViewerExclusions): Promise<ActivityDetailRecord> {
    return this.getActivityDetailUseCase.execute(viewerId, activityId, exclusions);
  }

  /**
   * The author edits their processed activity (ADR-033 §4) and gets its detail back. The caller
   * adds author and engagement, as for `getDetail`.
   */
  async update(userId: string, activityId: string, request: UpdateActivityRequest): Promise<ActivityDetailRecord> {
    await this.updateActivityUseCase.execute(userId, activityId, request);
    return this.getActivityDetailUseCase.execute(userId, activityId);
  }

  /** The author deletes their activity unless it is `processing` (ADR-031 §13, ADR-033 §6). */
  delete(userId: string, activityId: string): Promise<void> {
    return this.deleteActivityUseCase.execute(userId, activityId);
  }

  // --- Media upload (ADR-037 §4) ---

  /** Pre-signed `PUT`s for a Media's files, for the author in any state; writes nothing. */
  requestMediaUploadUrls(
    userId: string,
    activityId: string,
    request: MediaUploadUrlsRequest,
  ): Promise<MediaUploadUrlsResponse> {
    return this.requestMediaUploadUrlsUseCase.execute(userId, activityId, request);
  }

  /**
   * Confirms a Media whose files are in the bucket and inserts its row, idempotent on its id. The
   * caller signs the returned record.
   */
  confirmMedia(userId: string, activityId: string, request: ConfirmMediaRequest): Promise<ConfirmMediaResult> {
    return this.confirmMediaUseCase.execute(userId, activityId, request);
  }

  /** Deletes a Media's row, then its folder; also when the Media is already gone. */
  deleteMedia(userId: string, activityId: string, mediaId: string): Promise<void> {
    return this.deleteMediaUseCase.execute(userId, activityId, mediaId);
  }

  // --- Progrès and Statistiques (ADR-036 §4) ---

  /** The athlete's own 12 weeks and Streak for one active sport; `422` for an unknown sport. */
  getProgress(userId: string, sportTypeCode: string): Promise<ProgressResponse> {
    return this.getProgressUseCase.execute(userId, sportTypeCode);
  }

  /**
   * An athlete's statistics over the Activities `viewerId` may see; all sports when
   * `sportTypeCode` is omitted, `422` for an unknown one. The caller checks the athlete exists.
   */
  getAthleteStats(viewerId: string, athleteId: string, sportTypeCode?: string): Promise<AthleteStatsResponse> {
    return this.getAthleteStatsUseCase.execute(viewerId, athleteId, sportTypeCode);
  }

  /**
   * Activity count, Streak and sports of an athlete's profile header, over the Activities
   * `viewerId` may see (ADR-036 §3). The caller checks the athlete exists.
   */
  getAthleteProfileFigures(viewerId: string, athleteId: string): Promise<AthleteProfileFigures> {
    return this.getAthleteProfileFiguresUseCase.execute(viewerId, athleteId);
  }

  // --- File import (ADR-028) ---

  createImport(userId: string, request: CreateActivityImportRequest): Promise<CreateActivityImportResult> {
    return this.createActivityImportUseCase.execute(userId, request);
  }

  requestImportUploadUrl(userId: string, importId: string): Promise<UploadUrlResponse> {
    return this.requestImportUploadUrlUseCase.execute(userId, importId);
  }

  completeImport(userId: string, importId: string, requestId?: string): Promise<ActivityImport> {
    return this.completeActivityImportUseCase.execute(userId, importId, requestId);
  }

  getImport(userId: string, importId: string): Promise<ActivityImport> {
    return this.getActivityImportsUseCase.getOne(userId, importId);
  }

  listImports(userId: string, query: ListActivityImportsQuery): Promise<ListActivityImportsResponse> {
    return this.getActivityImportsUseCase.list(userId, query);
  }

  /** Called by `apps/worker`'s `import-activity` processor (ADR-028 §4). */
  importFromFile(job: ImportActivityJob): Promise<ImportActivityResult> {
    return this.importActivityFromFileUseCase.execute(job);
  }

  /** Last technical attempt of `import-activity` failed (ADR-028 §7). */
  markImportFailed(job: ImportActivityJob): Promise<void> {
    return this.importActivityFromFileUseCase.markTechnicalFailure(job);
  }

  /** Backoffice reprocessing of a failed import (ADR-028 §7). */
  reprocessImport(importId: string, requestId?: string): Promise<ActivityImport> {
    return this.reprocessActivityImportUseCase.execute(importId, requestId);
  }

  // --- Backoffice (ADR-038 §11) ---

  /** Every Activity, private ones included, newest created first. The caller adds the athletes. */
  listForAdmin(
    filter: AdminActivityFilter,
    page: { page: number; pageSize: number },
  ): Promise<{ rows: AdminActivityRow[]; total: number }> {
    return this.listAdminActivitiesUseCase.execute(filter, page);
  }

  /** Any Activity with its public trace only; `404 activity_not_found` for an unknown id. */
  getForAdmin(activityId: string): Promise<AdminActivityRecord> {
    return this.getAdminActivityUseCase.execute(activityId);
  }

  /**
   * « Retraiter »: a `failed` Activity back to `processing` and enqueued again (ADR-019 §6);
   * `409 not_failed` otherwise. Not to be confused with {@link reprocess}, the worker's job.
   */
  reprocessFailed(activityId: string, requestId?: string): Promise<ActivityRecord> {
    return this.reprocessFailedActivityUseCase.execute(activityId, requestId);
  }

  /** Sanction: deletes the Activity as its author would, without the author check. */
  deleteAsSanction(activityId: string): Promise<ActivityLabel> {
    return this.deleteActivityAsSanctionUseCase.execute(activityId);
  }

  /** Sanction: deletes a Media as the author would; `404 media_not_found` if already gone. */
  removeMediaAsSanction(activityId: string, mediaId: string): Promise<ActivityLabel> {
    return this.removeMediaAsSanctionUseCase.execute(activityId, mediaId);
  }

  /** Sanction: default title, no description. */
  resetText(activityId: string): Promise<ActivityTextReset> {
    return this.resetActivityTextUseCase.execute(activityId);
  }

  /** Batch read: how e-mails and the backoffice name these Activities (ADR-038 §4). */
  getLabels(activityIds: string[]): Promise<ActivityLabel[]> {
    return this.adminActivities.findLabels(activityIds);
  }

  /**
   * The user sheet's « Activité » section (ADR-038 §5): every Activity of the athlete, private
   * and unprocessed ones included, and the start of the latest.
   */
  getAdminSummary(userId: string): Promise<{ activityCount: number; lastActivityAt: Date | null }> {
    return this.adminActivities.findSummary(userId);
  }

  /** Batch read: the ids among `mediaIds` of Media that still exist (Journal links). */
  getExistingMediaIds(mediaIds: string[]): Promise<Set<string>> {
    return this.adminActivities.findExistingMediaIds(mediaIds);
  }
}
