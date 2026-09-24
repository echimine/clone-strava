import { Module, type DynamicModule } from "@nestjs/common";
import type { Database } from "@repo/db";
import { DATABASE } from "../infrastructure/index.js";
import { AUTH_INSTANCE, type AuthModuleOptions } from "./auth.constants.js";
import { createAuthInstance } from "./create-auth-instance.js";
import { AuthService } from "./auth.service.js";

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
      providers: [
        { provide: AUTH_MODULE_OPTIONS, useValue: options },
        {
          provide: AUTH_INSTANCE,
          useFactory: (db: Database, opts: AuthModuleOptions) => createAuthInstance(db, opts),
          inject: [DATABASE, AUTH_MODULE_OPTIONS],
        },
        AuthService,
      ],
      exports: [AuthService, AUTH_INSTANCE],
    };
  }
}
