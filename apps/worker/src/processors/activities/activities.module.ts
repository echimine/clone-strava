import { BullModule } from "@nestjs/bullmq";
import { Module } from "@nestjs/common";
import { ACTIVITIES_QUEUE_NAME, SEGMENTS_QUEUE_NAME } from "@repo/contracts";
import { ActivitiesModule } from "@repo/core/activities";
import { ProcessActivityProcessor } from "./process-activity.processor.js";
import { ReconciliationScheduler } from "./reconciliation.scheduler.js";

@Module({
  imports: [
    // `ActivitiesModule` (core) for `ActivitiesService`. It registers the
    // `activities` queue for its own internal use but does not export that
    // `Queue` provider (only `ActivitiesService`, ADR-021 §6), so it is
    // registered again here for `@InjectQueue` (`ReconciliationScheduler`)
    // -- `registerQueue` for the same name from multiple modules is
    // additive/idempotent. `segments` is registered here only as a
    // producer (job chaining, ADR-021 §2 rule 2); its own `Processor` lives
    // in `SegmentsProcessorModule`.
    ActivitiesModule,
    BullModule.registerQueue({ name: ACTIVITIES_QUEUE_NAME }, { name: SEGMENTS_QUEUE_NAME }),
  ],
  providers: [ProcessActivityProcessor, ReconciliationScheduler],
})
export class ActivitiesProcessorModule {}
