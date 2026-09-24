import { Module } from "@nestjs/common";
import { createRealtimePublisher } from "@repo/realtime";
import { REDIS, type Redis } from "../infrastructure/index.js";
import { REALTIME_PUBLISHER } from "./realtime.constants.js";
import { RealtimeBridge } from "./listeners/realtime-bridge.listener.js";

/**
 * `realtime` platform module (ADR-021 §1/§4): owns no table, no business
 * rule. Requires `REDIS` (provided globally by `CoreInfrastructureModule`,
 * see `../infrastructure`). Loaded in `apps/api` and `apps/worker`
 * (ADR-021 §4 "both processes emit events that may concern the mobile
 * app"), never in `apps/realtime` itself (ADR-021 §8: it has no `@repo/
 * core`, no `@repo/db`).
 *
 * This is the only module in `packages/core` allowed to import
 * `@repo/realtime` (ADR-021 §2, §9 rule 4); domain modules never do.
 */
@Module({
  providers: [
    {
      provide: REALTIME_PUBLISHER,
      useFactory: (redis: Redis) => createRealtimePublisher(redis),
      inject: [REDIS],
    },
    RealtimeBridge,
  ],
  exports: [RealtimeBridge],
})
export class RealtimeBridgeModule {}
