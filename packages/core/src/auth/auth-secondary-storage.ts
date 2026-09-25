import type { Redis } from "../infrastructure/index.js";

/**
 * Adapts the shared `ioredis` connection to Better Auth's `SecondaryStorage`
 * contract (`@better-auth/core`'s `db/type.d.mts`), so `betterAuth()`'s
 * `secondaryStorage` option (session cache, `verification` token cache,
 * `rateLimit.storage: "secondary-storage"`, ADR-022 §4) is Redis-backed
 * instead of the in-memory default.
 *
 * `increment` is not optional: `rateLimit`'s secondary-storage path throws
 * `BetterAuthError` at request time without it (verified in the installed
 * `better-auth@1.7.6`'s `dist/api/rate-limiter/index.mjs`).
 */
export function createAuthSecondaryStorage(redis: Redis) {
  return {
    get: (key: string) => redis.get(key),

    // Atomic get+delete: ioredis 6 exposes Redis's own `GETDEL` (Redis >= 6.2).
    getAndDelete: (key: string) => redis.getdel(key),

    // Atomic post-increment counter, TTL applied only on creation (Better
    // Auth's own contract): `INCR` then `EXPIRE key ttl NX` so a later
    // increment within the same window never resets the expiry.
    increment: async (key: string, ttl: number): Promise<number> => {
      const result = await redis.multi().incr(key).expire(key, ttl, "NX").exec();
      const incrResult = result?.[0];
      if (!incrResult || incrResult[0]) {
        throw incrResult?.[0] ?? new Error(`Redis INCR failed for key "${key}"`);
      }
      return incrResult[1] as number;
    },

    set: (key: string, value: string, ttl?: number) =>
      ttl ? redis.set(key, value, "EX", ttl) : redis.set(key, value),

    delete: async (key: string): Promise<void> => {
      await redis.del(key);
    },
  };
}
