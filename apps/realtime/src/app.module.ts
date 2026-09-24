import { Module } from "@nestjs/common";
import { ConfigModule } from "./config/config.module.js";
import { GatewayModule } from "./gateway/gateway.module.js";
import { HealthModule } from "./health/health.module.js";
import { AppLoggingModule } from "./logging/logging.module.js";
import { RedisModule } from "./redis/redis.module.js";

/**
 * `apps/realtime` (ADR-010, ADR-021 §8): transport only. No `@repo/core`,
 * no `@repo/db` — the gateway authenticates locally and never touches the
 * database.
 */
@Module({
  imports: [ConfigModule, AppLoggingModule, RedisModule, GatewayModule, HealthModule],
})
export class AppModule {}
