import { Module } from "@nestjs/common";
import { ActivitiesModule } from "@repo/core/activities";
import { EngagementModule } from "@repo/core/engagement";
import { ItinerariesModule } from "@repo/core/itineraries";
import { SocialModule } from "@repo/core/social";
import { UsersModule } from "@repo/core/users";
import { AuthModule } from "../auth/auth.module.js";
import { FeedAssembler } from "../feed/feed-assembler.js";
import { MediaAssembler } from "../media/media-assembler.js";
import { IdentitiesModule } from "../identities/identities.module.js";
import { AthleteProfileAssembler } from "./athlete-profile-assembler.js";
import { AthletesController } from "./athletes.controller.js";
import { MeProfileController } from "./me-profile.controller.js";

/**
 * An athlete's profile, their Activities and the name edit (ADR-036 §3), composed from
 * `activities`, `social`, `users`, `itineraries` and `auth`, next to the feed.
 */
@Module({
  imports: [AuthModule, ActivitiesModule, EngagementModule, ItinerariesModule, SocialModule, UsersModule, IdentitiesModule],
  controllers: [AthletesController, MeProfileController],
  // Profile Activities are feed items (ADR-036 §3).
  providers: [AthleteProfileAssembler, FeedAssembler, MediaAssembler],
})
export class AthletesModule {}
