import { Module } from "@nestjs/common";
import { TerminusModule } from "@nestjs/terminus";
import { DbHealthIndicator } from "./db-health.indicator.js";
import { HealthController } from "./health.controller.js";
import { RedisHealthIndicator } from "./redis-health.indicator.js";

// `DATABASE`/`REDIS` come from `CoreInfrastructureModule`, `@Global()` and
// registered once in `app.module.ts` -- no need to import it here too.
@Module({
  imports: [TerminusModule],
  controllers: [HealthController],
  providers: [DbHealthIndicator, RedisHealthIndicator],
})
export class HealthModule {}
