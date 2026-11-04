import { Module } from "@nestjs/common";
import { SocialModule } from "@repo/core/social";
import { AuthModule } from "../auth/auth.module.js";
import { ViewerFilterModule } from "../viewer-filter/viewer-filter.module.js";
import { IdentitiesModule } from "../identities/identities.module.js";
import { AthleteFollowsController } from "./athlete-follows.controller.js";
import { FollowListAssembler } from "./follow-list-assembler.js";
import { MeFollowsController } from "./me-follows.controller.js";

/** Follows between athletes (ADR-036 §1): `social` rules, identities assembled here. */
@Module({
  imports: [AuthModule, SocialModule, IdentitiesModule, ViewerFilterModule],
  controllers: [AthleteFollowsController, MeFollowsController],
  providers: [FollowListAssembler],
})
export class FollowsModule {}
