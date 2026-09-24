import { Controller, Get } from "@nestjs/common";
import { HealthCheck, HealthCheckService, type HealthIndicatorResult } from "@nestjs/terminus";
import { DbHealthIndicator } from "./db-health.indicator.js";
import { RedisHealthIndicator } from "./redis-health.indicator.js";

/**
 * `GET /health` (ADR-009 §"api stack", ADR-018 §6): database + Redis.
 * Public route, excluded from the global `/v1` prefix, from rate limiting
 * and from authentication (ADR-018 §6).
 */
@Controller("health")
export class HealthController {
  constructor(
    private readonly health: HealthCheckService,
    private readonly dbIndicator: DbHealthIndicator,
    private readonly redisIndicator: RedisHealthIndicator,
  ) {}

  @Get()
  @HealthCheck()
  check() {
    return this.health.check([
      async (): Promise<HealthIndicatorResult> => this.dbIndicator.isHealthy("database"),
      async (): Promise<HealthIndicatorResult> => this.redisIndicator.isHealthy("redis"),
    ]);
  }
}
