import { Controller, Get, Query, UseGuards } from "@nestjs/common";
import { createZodDto, ZodResponse } from "nestjs-zod";
import {
  athleteSearchQuerySchema,
  athleteSearchResponseSchema,
  type AthleteSearchResponse,
} from "@repo/contracts";
import { SocialService } from "@repo/core/social";
import { UsersService } from "@repo/core/users";
import { CurrentUser } from "../auth/current-user.decorator.js";
import { SessionGuard, type AuthenticatedUser } from "../auth/session.guard.js";
import { AthleteIdentities } from "../identities/athlete-identities.js";

class AthleteSearchQueryDto extends createZodDto(athleteSearchQuerySchema) {}
class AthleteSearchResponseDto extends createZodDto(athleteSearchResponseSchema) {}

/**
 * `GET /v1/athletes/search?q=` (ADR-036 §2). The path is static: its module
 * is imported before any module routing `athletes/:id`, so `search` is never
 * taken for an athlete id.
 */
@Controller("athletes")
@UseGuards(SessionGuard)
export class AthleteSearchController {
  constructor(
    private readonly users: UsersService,
    private readonly social: SocialService,
    private readonly identities: AthleteIdentities,
  ) {}

  /**
   * At most 20 athletes whose profile name contains `q`, ignoring case and
   * accents, word starts first, then alphabetical; never the viewer.
   * `q` trimmed must hold 2 to 50 characters, otherwise `422 invalid_query`.
   */
  @Get("search")
  @ZodResponse({ status: 200, type: AthleteSearchResponseDto })
  async search(
    @Query() query: AthleteSearchQueryDto,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<AthleteSearchResponse> {
    const ids = await this.users.searchByName(query.q, user.userId);
    const [athlete, statuses] = await Promise.all([
      this.identities.resolve(ids),
      this.social.getFollowStatuses(user.userId, ids),
    ]);
    return {
      items: ids.map((id) => ({ athlete: athlete(id), viewerFollowStatus: statuses.get(id) ?? "none" })),
    };
  }
}
