import { Module } from "@nestjs/common";
import { BansService } from "./bans.service.js";
import { BanRepository } from "./repositories/ban.repository.js";

/**
 * Active Bans for the viewer filter (ADR-038 §7): needs only the global `DATABASE`, unlike
 * `AuthModule.forRoot`, which builds Better Auth.
 */
@Module({
  providers: [BanRepository, BansService],
  exports: [BansService],
})
export class BansModule {}
