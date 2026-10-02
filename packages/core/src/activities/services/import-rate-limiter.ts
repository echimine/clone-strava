import { Inject, Injectable, Logger } from "@nestjs/common";
import { ACTIVITY_IMPORT_RATE_LIMIT_PER_HOUR } from "@repo/contracts";
import { REDIS, type Redis } from "../../infrastructure/index.js";

const WINDOW_S = 3600;

/**
 * Fixed-window rate limit on new imports (ADR-028 §9): key
 * `ratelimit:activity-imports:{userId}`, `INCR` + `EXPIRE` on the first
 * hit. Fail-open: it protects the worker, it is not a security boundary.
 */
@Injectable()
export class ImportRateLimiter {
  private readonly logger = new Logger(ImportRateLimiter.name);

  constructor(@Inject(REDIS) private readonly redis: Redis) {}

  /** Counts one import; returns the seconds to wait when the limit is exceeded. */
  async hit(userId: string): Promise<{ allowed: true } | { allowed: false; retryAfterS: number }> {
    const key = `ratelimit:activity-imports:${userId}`;
    try {
      const countValue = await this.redis.incr(key);
      if (countValue === 1) {
        await this.redis.expire(key, WINDOW_S);
      }
      if (countValue <= ACTIVITY_IMPORT_RATE_LIMIT_PER_HOUR) {
        return { allowed: true };
      }
      const ttl = await this.redis.ttl(key);
      return { allowed: false, retryAfterS: ttl > 0 ? ttl : WINDOW_S };
    } catch (error) {
      this.logger.warn(`Import rate limit unavailable, letting the request through: ${String(error)}`);
      return { allowed: true };
    }
  }
}
