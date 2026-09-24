import { Module } from "@nestjs/common";
import { TerminusModule } from "@nestjs/terminus";
import { GatewayModule } from "../gateway/gateway.module.js";
import { RedisModule } from "../redis/redis.module.js";
import { HealthController } from "./health.controller.js";
import { RedisHealthIndicator } from "./redis-health.indicator.js";

@Module({
  imports: [TerminusModule, RedisModule, GatewayModule],
  controllers: [HealthController],
  providers: [RedisHealthIndicator],
})
export class HealthModule {}
