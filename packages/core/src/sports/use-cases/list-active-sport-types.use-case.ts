import { Injectable, NotImplementedException } from "@nestjs/common";
import { SportTypeRepository } from "../repositories/sport-type.repository.js";
import type { SportType } from "../domain/sport-type.js";

@Injectable()
export class ListActiveSportTypesUseCase {
  constructor(private readonly sportTypes: SportTypeRepository) {}

  async execute(): Promise<SportType[]> {
    throw new NotImplementedException();
  }
}
