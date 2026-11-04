import { Module } from "@nestjs/common";
import { SocialModule } from "@repo/core/social";
import { AuthModule } from "../auth/auth.module.js";
import { IdentitiesModule } from "../identities/identities.module.js";
import { MeBlocksController } from "./me-blocks.controller.js";

/** Blocks between athletes (ADR-038 §8): `social` rules, identities assembled here. */
@Module({
  imports: [AuthModule, SocialModule, IdentitiesModule],
  controllers: [MeBlocksController],
})
export class BlocksModule {}
