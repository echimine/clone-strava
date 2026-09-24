import { Module } from "@nestjs/common";
import { SportTypeRepository } from "./repositories/sport-type.repository.js";
import { ListActiveSportTypesUseCase } from "./use-cases/list-active-sport-types.use-case.js";
import { SportsService } from "./sports.service.js";

/** `sports` module (ADR-021 §1, layer 0). Exports only its service. */
@Module({
  providers: [SportTypeRepository, ListActiveSportTypesUseCase, SportsService],
  exports: [SportsService],
})
export class SportsModule {}
