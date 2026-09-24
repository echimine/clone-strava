import {
  Global,
  Inject,
  Injectable,
  Module,
  type DynamicModule,
  type OnApplicationShutdown,
} from "@nestjs/common";
import { createDb } from "@repo/db";
import { Redis } from "ioredis";
import { DATABASE, REDIS } from "./tokens.js";



export interface CoreInfrastructureOptions {
  databaseUrl: string;
  redisUrl: string;
}

const CORE_INFRASTRUCTURE_OPTIONS = Symbol("CORE_INFRASTRUCTURE_OPTIONS");
/** Internal token for the `{ db, pool }` pair `createDb` returns (ADR-003, `packages/db`). */
const DATABASE_CONNECTION = Symbol("DATABASE_CONNECTION");

/**
 * Closes the underlying `pg` pool and the `ioredis` connection on shutdown.
 * `DATABASE` / `REDIS` only expose the client instances to feature modules
 * (ADR-021 §2 rule 5: cross-module code never touches connection
 * internals), so the teardown lives in its own provider instead.
 */
@Injectable()
class InfrastructureLifecycle implements OnApplicationShutdown {
  constructor(
    @Inject(DATABASE_CONNECTION) private readonly connection: ReturnType<typeof createDb>,
    @Inject(REDIS) private readonly redis: Redis,
  ) {}

  async onApplicationShutdown(): Promise<void> {
    await Promise.allSettled([this.connection.pool.end(), this.redis.quit()]);
  }
}

/**
 * Global module providing the two pieces of shared infrastructure every
 * domain and platform module depends on (ADR-021 §6): the Drizzle
 * `DATABASE` connection and the `ioredis` `REDIS` connection.
 *
 * `@Global()`: `apps/api` and `apps/worker` register it once at the root
 * module with `forRoot(...)`, every feature module then injects `DATABASE`
 * / `REDIS` without re-importing this module.
 */
@Global()
@Module({})
export class CoreInfrastructureModule {
  static forRoot(options: CoreInfrastructureOptions): DynamicModule {
    return {
      module: CoreInfrastructureModule,
      providers: [
        { provide: CORE_INFRASTRUCTURE_OPTIONS, useValue: options },
        {
          provide: DATABASE_CONNECTION,
          useFactory: (opts: CoreInfrastructureOptions) => createDb(opts.databaseUrl),
          inject: [CORE_INFRASTRUCTURE_OPTIONS],
        },
        {
          provide: DATABASE,
          useFactory: (connection: ReturnType<typeof createDb>) => connection.db,
          inject: [DATABASE_CONNECTION],
        },
        {
          provide: REDIS,
          useFactory: (opts: CoreInfrastructureOptions) => new Redis(opts.redisUrl),
          inject: [CORE_INFRASTRUCTURE_OPTIONS],
        },
        InfrastructureLifecycle,
      ],
      exports: [DATABASE, REDIS],
    };
  }
}
