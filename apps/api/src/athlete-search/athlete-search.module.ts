import { Module } from "@nestjs/common";
import { SocialModule } from "@repo/core/social";
import { UsersModule } from "@repo/core/users";
import { AuthModule } from "../auth/auth.module.js";
import { IdentitiesModule } from "../identities/identities.module.js";
import { AthleteSearchController } from "./athlete-search.controller.js";

/**
 * Athlete search (ADR-036 §2): `users` finds the ids, identities and follow
 * statuses are assembled here. Import it before any module routing
 * `athletes/:id`, so the static `athletes/search` route is registered first.
 */
@Module({
  imports: [AuthModule, UsersModule, SocialModule, IdentitiesModule],
  controllers: [AthleteSearchController],
})
export class AthleteSearchModule {}
