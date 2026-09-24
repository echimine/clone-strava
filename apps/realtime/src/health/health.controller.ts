import { Controller, Get } from "@nestjs/common";
import { HealthCheck, HealthCheckService, type HealthIndicatorResult } from "@nestjs/terminus";
import { GatewayService } from "../gateway/gateway.service.js";
import { RedisHealthIndicator } from "./redis-health.indicator.js";

/**
 * `GET /health` (ADR-010 §5, ADR-018 §6): Redis reachable, plus the number
 * of currently open connections. Public route, outside `/v1` (this app has
 * no versioned prefix at all).
 */
@Controller("health")
export class HealthController {
  constructor(
    private readonly health: HealthCheckService,
    private readonly redisIndicator: RedisHealthIndicator,
    private readonly gateway: GatewayService,
  ) {}

  @Get()
  @HealthCheck()
  check() {
    return this.health.check([
      async (): Promise<HealthIndicatorResult> => this.redisIndicator.isHealthy("redis"),
      (): HealthIndicatorResult => ({
        connections: { status: "up", count: this.gateway.getConnectionCount() },
      }),
    ]);
  }
}
