import { Inject, Injectable } from "@nestjs/common";
import { HealthIndicatorService } from "@nestjs/terminus";
import { REDIS, type Redis } from "@repo/core/infrastructure";

@Injectable()
export class RedisHealthIndicator {
  constructor(
    private readonly healthIndicatorService: HealthIndicatorService,
    @Inject(REDIS) private readonly redis: Redis,
  ) {}

  async isHealthy(key: string) {
    const indicator = this.healthIndicatorService.check(key);
    try {
      await this.redis.ping();
      return indicator.up();
    } catch (error) {
      return indicator.down(error instanceof Error ? error.message : "unknown error");
    }
  }
}
