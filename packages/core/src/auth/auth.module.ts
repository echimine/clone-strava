import { BullModule } from "@nestjs/bullmq";
import { Module, type DynamicModule } from "@nestjs/common";
import { EventEmitter2 } from "@nestjs/event-emitter";
import { AVATARS_QUEUE_NAME } from "@repo/contracts";
import type { Database } from "@repo/db";
import { AnalyticsService } from "../analytics/index.js";
import { DATABASE, REDIS, type Redis } from "../infrastructure/index.js";
import { NotificationsModule, NotificationsService } from "../notifications/index.js";
import { AUTH_INSTANCE, type AuthModuleOptions } from "./auth.constants.js";
import { createAuthInstance } from "./create-auth-instance.js";
import { AuthService } from "./auth.service.js";
import { AuthAdminStatsRepository } from "./repositories/auth-admin-stats.repository.js";
import { AuthUserRepository } from "./repositories/auth-user.repository.js";
import { GoogleAvatarCopyEnqueuer } from "./services/google-avatar-copy-enqueuer.js";
import { AccountReader } from "./services/account-reader.js";
import { AuthAdminApi } from "./services/auth-admin-api.js";
import { BackfillGoogleAvatarsUseCase } from "./use-cases/backfill-google-avatars.use-case.js";
import { BanUserUseCase } from "./use-cases/ban-user.use-case.js";
import { SetUserRoleUseCase } from "./use-cases/set-user-role.use-case.js";

export type { AuthModuleOptions } from "./auth.constants.js";

const AUTH_MODULE_OPTIONS = Symbol("AUTH_MODULE_OPTIONS");

/**
 * `auth` module (ADR-021 §1: layer 0, owns `user`/`session`/`account`/
 * `verification`). Builds the Better Auth instance (`create-auth-instance.
 * ts`) on top of the shared `DATABASE` connection (ADR-003, ADR-009 §3).
 *
 * Exports `AuthService` and `AUTH_INSTANCE`: unlike other modules'
 * "exports only the service" (ADR-021 §6), `apps/api` also needs the raw
 * instance to mount Better Auth's own HTTP handler at `/api/auth/*`
 * (ADR-009 §3) — a framework-mounting need, not a business-logic call
 * routed around `AuthService`.
 */
@Module({})
export class AuthModule {
  static forRoot(options: AuthModuleOptions): DynamicModule {
    return {
      module: AuthModule,
      // This `NotificationsService` instance is only ever used here to send
      // auth emails (`sendEmail`), never to verify a webhook signature,
      // so it has no `webhookSecret` — `webhooks.module.ts` imports its own
      // `NotificationsModule.forRoot(...)` with the real one for that purpose.
      // The `avatars` queue: the account hook enqueues the Google photo copy (ADR-037 §2), so
      // every app importing this module also needs `BullModule.forRoot`.
      imports: [
        NotificationsModule.forRoot({ apiKey: options.resendApiKey }),
        BullModule.registerQueue({ name: AVATARS_QUEUE_NAME }),
      ],
      providers: [
        { provide: AUTH_MODULE_OPTIONS, useValue: options },
        {
          provide: AUTH_INSTANCE,
          useFactory: (
            db: Database,
            redis: Redis,
            notifications: NotificationsService,
            analytics: AnalyticsService,
            googleAvatars: GoogleAvatarCopyEnqueuer,
            opts: AuthModuleOptions,
            events: EventEmitter2 | undefined,
          ) => createAuthInstance(db, redis, notifications, analytics, googleAvatars, opts, events ?? null),
          // `AnalyticsService` comes from the global `AnalyticsModule` each app registers.
          inject: [
            DATABASE,
            REDIS,
            NotificationsService,
            AnalyticsService,
            GoogleAvatarCopyEnqueuer,
            AUTH_MODULE_OPTIONS,
            // The app's global `EventEmitterModule`, when it has one: the admin access events
            // the API records in the Journal (ADR-038 §3).
            { token: EventEmitter2, optional: true },
          ],
        },
        AuthAdminStatsRepository,
        AuthUserRepository,
        GoogleAvatarCopyEnqueuer,
        BackfillGoogleAvatarsUseCase,
        AccountReader,
        AuthAdminApi,
        BanUserUseCase,
        SetUserRoleUseCase,
        AuthService,
      ],
      exports: [AuthService, AUTH_INSTANCE],
    };
  }
}
