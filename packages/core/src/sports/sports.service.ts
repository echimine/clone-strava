import { Injectable, NotImplementedException } from "@nestjs/common";
import { SportTypeRepository } from "./repositories/sport-type.repository.js";
import { ListActiveSportTypesUseCase } from "./use-cases/list-active-sport-types.use-case.js";
import type { SportType } from "./domain/sport-type.js";

/** Public facade of the `sports` module (ADR-021 §1, layer 0). */
@Injectable()
export class SportsService {
  constructor(
    private readonly sportTypes: SportTypeRepository,
    private readonly listActiveSportTypes: ListActiveSportTypesUseCase,
  ) {}

  list(): Promise<SportType[]> {
    return this.listActiveSportTypes.execute();
  }

  async getByCode(_code: string): Promise<SportType> {
    throw new NotImplementedException();
  }
}
