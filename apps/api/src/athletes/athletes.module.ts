import { Module } from "@nestjs/common";
import { ActivitiesModule } from "@repo/core/activities";
import { EngagementModule } from "@repo/core/engagement";
import { ItinerariesModule } from "@repo/core/itineraries";
import { SocialModule } from "@repo/core/social";
import { SportsModule } from "@repo/core/sports";
import { UsersModule } from "@repo/core/users";
import { AuthModule } from "../auth/auth.module.js";
import { ViewerFilterModule } from "../viewer-filter/viewer-filter.module.js";
import { FeedAssembler } from "../feed/feed-assembler.js";
import { MediaAssembler } from "../media/media-assembler.js";
import { IdentitiesModule } from "../identities/identities.module.js";
import { AthleteGalleryController } from "./athlete-gallery.controller.js";
import { AthleteProfileAssembler } from "./athlete-profile-assembler.js";
import { AthletesController } from "./athletes.controller.js";
import { SportsActiveCatalog } from "../me/sports-active-catalog.js";
import { MeProfileController } from "./me-profile.controller.js";

/**
 * An athlete's profile, their Activities and the name edit (ADR-036 §3), and their Gallery
 * (ADR-037 §9), composed from `activities`, `social`, `users`, `itineraries` and `auth`, next to
 * the feed.
 */
@Module({
  imports: [AuthModule, ActivitiesModule, EngagementModule, ItinerariesModule, SocialModule, SportsModule, UsersModule, IdentitiesModule, ViewerFilterModule],
  controllers: [AthletesController, AthleteGalleryController, MeProfileController],
  // Profile Activities are feed items (ADR-036 §3).
  providers: [AthleteProfileAssembler, FeedAssembler, MediaAssembler, SportsActiveCatalog],
})
export class AthletesModule {}
