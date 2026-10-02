import { Injectable } from "@nestjs/common";
import { SportTypeRepository } from "../repositories/sport-type.repository.js";
import { toSportType, type SportType } from "../domain/sport-type.js";

@Injectable()
export class ListActiveSportTypesUseCase {
  constructor(private readonly sportTypes: SportTypeRepository) {}

  async execute(): Promise<SportType[]> {
    const rows = await this.sportTypes.listActive();
    return rows.map(toSportType);
  }
}
