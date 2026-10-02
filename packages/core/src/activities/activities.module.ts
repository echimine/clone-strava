import { Module } from "@nestjs/common";
import { BullModule } from "@nestjs/bullmq";
import { ACTIVITIES_QUEUE_NAME, IMPORTS_QUEUE_NAME } from "@repo/contracts";
import { SportsModule } from "../sports/index.js";
import { UsersModule } from "../users/index.js";
import { SocialModule } from "../social/index.js";
import { ActivityRepository } from "./repositories/activity.repository.js";
import { ActivityStatsRepository } from "./repositories/activity-stats.repository.js";
import { ActivityTrackRepository } from "./repositories/activity-track.repository.js";
import { CreateActivityUseCase } from "./use-cases/create-activity.use-case.js";
import { RequestUploadUrlUseCase } from "./use-cases/request-upload-url.use-case.js";
import { CompleteActivityUseCase } from "./use-cases/complete-activity.use-case.js";
import { ProcessActivityUseCase } from "./use-cases/process-activity.use-case.js";
import { ReconcileStuckActivitiesUseCase } from "./use-cases/reconcile-stuck-activities.use-case.js";
import { GetActivitiesUseCase } from "./use-cases/get-activities.use-case.js";
import { ActivityImportRepository } from "./repositories/activity-import.repository.js";
import { CreateActivityImportUseCase } from "./use-cases/create-activity-import.use-case.js";
import { RequestImportUploadUrlUseCase } from "./use-cases/request-import-upload-url.use-case.js";
import { CompleteActivityImportUseCase } from "./use-cases/complete-activity-import.use-case.js";
import { GetActivityImportsUseCase } from "./use-cases/get-activity-imports.use-case.js";
import { ImportActivityFromFileUseCase } from "./use-cases/import-activity-from-file.use-case.js";
import { ReprocessActivityImportUseCase } from "./use-cases/reprocess-activity-import.use-case.js";
import { ImportRateLimiter } from "./services/import-rate-limiter.js";
import { ImportJobEnqueuer } from "./services/import-job-enqueuer.js";
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
    ActivityRepository,
    ActivityStatsRepository,
    ActivityTrackRepository,
    CreateActivityUseCase,
    RequestUploadUrlUseCase,
    CompleteActivityUseCase,
    ProcessActivityUseCase,
    ReconcileStuckActivitiesUseCase,
    GetActivitiesUseCase,
    ActivityImportRepository,
    ImportRateLimiter,
    ImportJobEnqueuer,
    CreateActivityImportUseCase,
    RequestImportUploadUrlUseCase,
    CompleteActivityImportUseCase,
    GetActivityImportsUseCase,
    ImportActivityFromFileUseCase,
    ReprocessActivityImportUseCase,
    ActivitiesService,
  ],
  exports: [ActivitiesService],
})
export class ActivitiesModule {}
