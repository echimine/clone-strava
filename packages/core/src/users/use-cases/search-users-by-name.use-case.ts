import { Injectable, UnprocessableEntityException } from "@nestjs/common";
import { UserProfileRepository } from "../repositories/user-profile.repository.js";
import {
  NAME_QUERY_MAX_LENGTH,
  NAME_QUERY_MIN_LENGTH,
  NAME_SEARCH_LIMIT,
  parseNameQuery,
} from "../domain/name-search.js";

/**
 * Athlete search by profile name (ADR-036 §2): case- and accent-insensitive
 * substring matching, word starts first, then alphabetical.
 */
@Injectable()
export class SearchUsersByNameUseCase {
  constructor(private readonly userProfiles: UserProfileRepository) {}

  /** Ids of at most 20 matching users other than `excludeUserId`; `422 invalid_query` on a bad query. */
  execute(rawQuery: string | undefined, excludeUserId: string): Promise<string[]> {
    const query = parseNameQuery(rawQuery);
    if (query === null) {
      throw new UnprocessableEntityException({
        code: "invalid_query",
        message: `The search must hold ${NAME_QUERY_MIN_LENGTH} to ${NAME_QUERY_MAX_LENGTH} characters`,
      });
    }
    return this.userProfiles.searchIdsByName(query, excludeUserId, NAME_SEARCH_LIMIT);
  }
}
