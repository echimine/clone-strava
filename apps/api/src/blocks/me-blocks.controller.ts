import { Controller, Delete, Get, HttpCode, HttpStatus, Param, ParseUUIDPipe, Put, UseGuards } from "@nestjs/common";
import { ApiResponse } from "@nestjs/swagger";
import { createZodDto, ZodResponse } from "nestjs-zod";
import { blockedAthleteListResponseSchema, type BlockedAthleteListResponse } from "@repo/contracts";
import { SocialService } from "@repo/core/social";
import { CurrentUser } from "../auth/current-user.decorator.js";
import { SessionGuard, type AuthenticatedUser } from "../auth/session.guard.js";
import { AthleteIdentities } from "../identities/athlete-identities.js";

class BlockedAthleteListResponseDto extends createZodDto(blockedAthleteListResponseSchema) {}

/**
 * Blocks (ADR-038 §8): two athletes become nonexistent to each other (profile, search, feed,
 * lists, Activities, Media, comments, kudos) through the viewer filter. Online only, no limit,
 * no notice to anyone.
 */
@Controller("me/blocks")
@UseGuards(SessionGuard)
export class MeBlocksController {
  constructor(
    private readonly social: SocialService,
    private readonly identities: AthleteIdentities,
  ) {}

  /** "Athlètes bloqués": those the viewer blocked, most recent first; never who blocked them. */
  @Get()
  @ZodResponse({ status: 200, type: BlockedAthleteListResponseDto })
  async list(@CurrentUser() user: AuthenticatedUser): Promise<BlockedAthleteListResponse> {
    const blocks = await this.social.listBlocks(user.userId);
    const athlete = await this.identities.resolve(blocks.map((block) => block.athleteId));
    return {
      items: blocks.map((block) => ({ athlete: athlete(block.athleteId), blockedAt: block.blockedAt.toISOString() })),
    };
  }

  /**
   * Blocks an athlete and deletes the follows and follow requests between both, in both
   * directions. Idempotent. `422 cannot_block_self`, `404 athlete_not_found`.
   */
  @Put(":athleteId")
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiResponse({ status: 204, description: "Blocked" })
  async block(
    @Param("athleteId", ParseUUIDPipe) athleteId: string,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<void> {
    await this.identities.assertExists(athleteId);
    await this.social.block(user.userId, athleteId);
  }

  /** Lifts the viewer's Block; follows do not come back. Idempotent. */
  @Delete(":athleteId")
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiResponse({ status: 204, description: "Unblocked, or was not blocked" })
  unblock(@Param("athleteId", ParseUUIDPipe) athleteId: string, @CurrentUser() user: AuthenticatedUser): Promise<void> {
    return this.social.unblock(user.userId, athleteId);
  }
}
