import { Module } from "@nestjs/common";
import { HeartbeatService } from "./heartbeat.service.js";

// `REDIS` comes from `CoreInfrastructureModule`, `@Global()` and registered
// once in `worker.module.ts` -- no need to import it here too.
@Module({
  providers: [HeartbeatService],
})
export class HeartbeatModule {}
