import { Module } from "@nestjs/common";
import { BullModule } from "@nestjs/bullmq";
import { ACTIVITIES_QUEUE_NAME, IMPORTS_QUEUE_NAME } from "@repo/contracts";
import { SportsModule } from "../sports/index.js";
import { UsersModule } from "../users/index.js";
import { SocialModule } from "../social/index.js";
import { ActivityAdminStatsRepository } from "./repositories/activity-admin-stats.repository.js";
import { ActivityRepository } from "./repositories/activity.repository.js";
import { ActivityStatsRepository } from "./repositories/activity-stats.repository.js";
import { ActivityTrackRepository } from "./repositories/activity-track.repository.js";
import { ActivityAnalysisRepository } from "./repositories/activity-analysis.repository.js";
import { ActivityMediaRepository } from "./repositories/activity-media.repository.js";
import { CreateActivityUseCase } from "./use-cases/create-activity.use-case.js";
import { RequestUploadUrlUseCase } from "./use-cases/request-upload-url.use-case.js";
import { CompleteActivityUseCase } from "./use-cases/complete-activity.use-case.js";
import { ProcessActivityUseCase } from "./use-cases/process-activity.use-case.js";
import { ReconcileStuckActivitiesUseCase } from "./use-cases/reconcile-stuck-activities.use-case.js";
import { GetActivitiesUseCase } from "./use-cases/get-activities.use-case.js";
import { GetActivityMediaUseCase } from "./use-cases/get-activity-media.use-case.js";
import { ActivityImportRepository } from "./repositories/activity-import.repository.js";
import { CreateActivityImportUseCase } from "./use-cases/create-activity-import.use-case.js";
import { RequestImportUploadUrlUseCase } from "./use-cases/request-import-upload-url.use-case.js";
import { CompleteActivityImportUseCase } from "./use-cases/complete-activity-import.use-case.js";
import { GetActivityImportsUseCase } from "./use-cases/get-activity-imports.use-case.js";
import { ImportActivityFromFileUseCase } from "./use-cases/import-activity-from-file.use-case.js";
import { ReprocessActivityImportUseCase } from "./use-cases/reprocess-activity-import.use-case.js";
import { GetFeedPageUseCase } from "./use-cases/get-feed-page.use-case.js";
import { GetVisibleActivityUseCase } from "./use-cases/get-visible-activity.use-case.js";
import { GetActivityDetailUseCase } from "./use-cases/get-activity-detail.use-case.js";
import { DeleteActivityUseCase } from "./use-cases/delete-activity.use-case.js";
import { UpdateActivityUseCase } from "./use-cases/update-activity.use-case.js";
import { ReprocessActivityUseCase } from "./use-cases/reprocess-activity.use-case.js";
import { OfficialValuesService } from "./services/official-values.js";
import { ImportRateLimiter } from "./services/import-rate-limiter.js";
import { ImportJobEnqueuer } from "./services/import-job-enqueuer.js";
import { ReprocessJobEnqueuer } from "./services/reprocess-job-enqueuer.js";
import { ActivityAggregateRepository } from "./repositories/activity-aggregate.repository.js";
import { AggregateScopeResolver } from "./services/aggregate-scope-resolver.js";
import { GetProgressUseCase } from "./use-cases/get-progress.use-case.js";
import { GetAthleteStatsUseCase } from "./use-cases/get-athlete-stats.use-case.js";
import { GetAthleteProfileFiguresUseCase } from "./use-cases/get-athlete-profile-figures.use-case.js";
import { GetAthleteActivitiesPageUseCase } from "./use-cases/get-athlete-activities-page.use-case.js";
import { GetAthleteGalleryPageUseCase } from "./use-cases/get-athlete-gallery-page.use-case.js";
import { FeedPageBuilder } from "./services/feed-page-builder.js";
import { BucketReferencesRepository } from "./repositories/bucket-references.repository.js";
import { SweepBucketUseCase } from "./use-cases/sweep-bucket.use-case.js";
import { AuthorActivityResolver } from "./services/author-activity-resolver.js";
import { RequestMediaUploadUrlsUseCase } from "./use-cases/request-media-upload-urls.use-case.js";
import { ConfirmMediaUseCase } from "./use-cases/confirm-media.use-case.js";
import { DeleteMediaUseCase } from "./use-cases/delete-media.use-case.js";
import { ActivityRemover } from "./services/activity-remover.js";
import { MediaRemover } from "./services/media-remover.js";
import { AdminActivityRepository } from "./repositories/admin-activity.repository.js";
import { ListAdminActivitiesUseCase } from "./use-cases/list-admin-activities.use-case.js";
import { GetAdminActivityUseCase } from "./use-cases/get-admin-activity.use-case.js";
import { ReprocessFailedActivityUseCase } from "./use-cases/reprocess-failed-activity.use-case.js";
import { DeleteActivityAsSanctionUseCase } from "./use-cases/delete-activity-as-sanction.use-case.js";
import { RemoveMediaAsSanctionUseCase } from "./use-cases/remove-media-as-sanction.use-case.js";
import { ResetActivityTextUseCase } from "./use-cases/reset-activity-text.use-case.js";
import { AdminFailureRepository } from "./repositories/admin-failure.repository.js";
import { ListAdminFailuresUseCase } from "./use-cases/list-admin-failures.use-case.js";
import { RecomputeActivityUseCase } from "./use-cases/recompute-activity.use-case.js";
import { RelaunchFailuresUseCase } from "./use-cases/relaunch-failures.use-case.js";
import { ActivitiesService } from "./activities.service.js";

/**
 * `activities` module (ADR-021 §1/§2: layer 2, may depend on `sports`,
 * `users`, `social`). Registers the `activities` queue as a producer
 * (ADR-011, ADR-021 §5); only `apps/worker` registers a processor for it.
 * Exports only its service.
 */
@Module({
  imports: [
    SportsModule,
    UsersModule,
    SocialModule,
    BullModule.registerQueue({ name: ACTIVITIES_QUEUE_NAME }, { name: IMPORTS_QUEUE_NAME }),
  ],
  providers: [
    ActivityAdminStatsRepository,
    ActivityRepository,
    ActivityStatsRepository,
    ActivityTrackRepository,
    ActivityAnalysisRepository,
    ActivityMediaRepository,
    CreateActivityUseCase,
    RequestUploadUrlUseCase,
    CompleteActivityUseCase,
    ProcessActivityUseCase,
    ReconcileStuckActivitiesUseCase,
    GetActivitiesUseCase,
    GetActivityMediaUseCase,
    ActivityImportRepository,
    ImportRateLimiter,
    ImportJobEnqueuer,
    ReprocessJobEnqueuer,
    CreateActivityImportUseCase,
    RequestImportUploadUrlUseCase,
    CompleteActivityImportUseCase,
    GetActivityImportsUseCase,
    ImportActivityFromFileUseCase,
    ReprocessActivityImportUseCase,
    GetFeedPageUseCase,
    GetVisibleActivityUseCase,
    GetActivityDetailUseCase,
    DeleteActivityUseCase,
    UpdateActivityUseCase,
    ReprocessActivityUseCase,
    OfficialValuesService,
    ActivityAggregateRepository,
    AggregateScopeResolver,
    GetProgressUseCase,
    GetAthleteStatsUseCase,
    GetAthleteProfileFiguresUseCase,
    GetAthleteActivitiesPageUseCase,
    GetAthleteGalleryPageUseCase,
    FeedPageBuilder,
    BucketReferencesRepository,
    SweepBucketUseCase,
    AuthorActivityResolver,
    RequestMediaUploadUrlsUseCase,
    ConfirmMediaUseCase,
    DeleteMediaUseCase,
    // Backoffice (ADR-038 §11)
    ActivityRemover,
    MediaRemover,
    AdminActivityRepository,
    ListAdminActivitiesUseCase,
    GetAdminActivityUseCase,
    ReprocessFailedActivityUseCase,
    DeleteActivityAsSanctionUseCase,
    RemoveMediaAsSanctionUseCase,
    ResetActivityTextUseCase,
    // Jobs screen, "Échecs" tab (ADR-038 §14)
    AdminFailureRepository,
    ListAdminFailuresUseCase,
    RecomputeActivityUseCase,
    RelaunchFailuresUseCase,
    ActivitiesService,
  ],
  exports: [ActivitiesService],
})
export class ActivitiesModule {}
