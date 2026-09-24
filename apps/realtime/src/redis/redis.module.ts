import { Inject, Module, type OnModuleDestroy } from "@nestjs/common";
import Redis from "ioredis";
import { ConfigModule } from "../config/config.module.js";
import { CONFIG, type RealtimeEnv } from "../config/env.js";

/** Injection token for the base `ioredis` client (ADR-010 §2). */
export const REDIS_CLIENT = Symbol("REDIS_CLIENT");

@Module({
  imports: [ConfigModule],
  providers: [
    {
      provide: REDIS_CLIENT,
      inject: [CONFIG],
      useFactory: (config: RealtimeEnv) =>
        new Redis(config.REDIS_URL, { maxRetriesPerRequest: null }),
    },
  ],
  exports: [REDIS_CLIENT],
})
export class RedisModule implements OnModuleDestroy {
  constructor(@Inject(REDIS_CLIENT) private readonly redis: Redis) {}

  async onModuleDestroy(): Promise<void> {
    await this.redis.quit();
  }
}
