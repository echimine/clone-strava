import { Body, Controller, HttpCode, HttpStatus, Put, UnprocessableEntityException, UseGuards } from "@nestjs/common";
import { ApiResponse } from "@nestjs/swagger";
import { createZodDto } from "nestjs-zod";
import { onboardingAnswersRequestSchema } from "@repo/contracts";
import { SportsService } from "@repo/core/sports";
import { UsersService } from "@repo/core/users";
import { CurrentUser } from "../auth/current-user.decorator.js";
import { SessionGuard, type AuthenticatedUser } from "../auth/session.guard.js";

class OnboardingAnswersRequestDto extends createZodDto(onboardingAnswersRequestSchema) {}

/** `PUT /v1/me/onboarding-answers` (ADR-035 §4, §5): the Onboarding answers become the profile. */
@Controller("me/onboarding-answers")
@UseGuards(SessionGuard)
export class OnboardingAnswersController {
  constructor(
    private readonly sportsService: SportsService,
    private readonly usersService: UsersService,
  ) {}

  /**
   * Fills only what the profile leaves empty, sports only if the athlete has
   * none: `204` for every valid request, even when nothing is written. `422`
   * for invalid answers, an age under 15, or an unknown or inactive sport.
   */
  @Put()
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiResponse({ status: 204, description: "Answers received" })
  async submit(@Body() body: OnboardingAnswersRequestDto, @CurrentUser() user: AuthenticatedUser): Promise<void> {
    // `users` depends on no module (ADR-021 §2): the sport codes are checked here.
    const activeCodes = new Set((await this.sportsService.list()).map((sport) => sport.code));
    if (!body.sportCodes.every((code) => activeCodes.has(code))) {
      const message = "Unknown or inactive sport type";
      throw new UnprocessableEntityException({
        code: "validation_error",
        message,
        details: [{ field: "sportCodes", message }],
      });
    }
    await this.usersService.submitOnboardingAnswers(user.userId, body);
  }
}
