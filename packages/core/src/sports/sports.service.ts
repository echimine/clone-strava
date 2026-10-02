import { Injectable } from "@nestjs/common";
import { SportTypeRepository } from "./repositories/sport-type.repository.js";
import { ListActiveSportTypesUseCase } from "./use-cases/list-active-sport-types.use-case.js";
import { toSportType, type SportType } from "./domain/sport-type.js";

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

  /** `undefined` for an unknown code; callers decide whether an inactive sport is acceptable. */
  async findByCode(code: string): Promise<SportType | undefined> {
    const row = await this.sportTypes.findByCode(code);
    return row ? toSportType(row) : undefined;
  }
}
