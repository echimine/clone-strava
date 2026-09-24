import { Module } from "@nestjs/common";
import { AuthModule as CoreAuthModule } from "@repo/core/auth";
import { loadConfig } from "../config/env.js";
import { AdminGuard } from "./admin.guard.js";
import { SessionGuard } from "./session.guard.js";

// `AuthModule.forRoot(...)` is synchronous (no DI injection of config), so
// the environment is loaded directly here, the same way `ConfigModule`
// does it -- both run once, at module-decoration time.
const config = loadConfig();
const coreAuthModule = CoreAuthModule.forRoot({
  secret: config.BETTER_AUTH_SECRET,
  baseUrl: config.BETTER_AUTH_URL,
  // No cross-origin frontend needs Better Auth's cookie today (ADR-009 §"api
  // stack": "no CORS: the backoffice goes through the Next.js proxy").
  trustedOrigins: [],
});

/**
 * Re-exports `@repo/core/auth`'s `AuthService` and `AUTH_INSTANCE` (the
 * latter needed by `main.ts` to mount Better Auth's own HTTP handler at
 * `/api/auth/*`, ADR-009 §3) alongside this app's guards, so every feature
 * module only needs `imports: [AuthModule]`.
 */
@Module({
  imports: [coreAuthModule],
  providers: [SessionGuard, AdminGuard],
  exports: [coreAuthModule, SessionGuard, AdminGuard],
})
export class AuthModule {}
