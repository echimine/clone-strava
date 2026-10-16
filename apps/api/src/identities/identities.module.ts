import { Module } from "@nestjs/common";
import { UsersModule } from "@repo/core/users";
import { AuthModule } from "../auth/auth.module.js";
import { AthleteIdentities } from "./athlete-identities.js";

/** Athlete identity assembly shared by the feed, the detail, comments and kudos (ADR-029 §2). */
@Module({
  imports: [AuthModule, UsersModule],
  providers: [AthleteIdentities],
  exports: [AthleteIdentities],
})
export class IdentitiesModule {}
