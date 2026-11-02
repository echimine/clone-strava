import { Body, Controller, HttpCode, HttpStatus, Put, UseGuards } from "@nestjs/common";
import { ApiResponse } from "@nestjs/swagger";
import { createZodDto } from "nestjs-zod";
import { onboardingAnswersRequestSchema } from "@repo/contracts";
import { UsersService } from "@repo/core/users";
import { CurrentUser } from "../auth/current-user.decorator.js";
import { SessionGuard, type AuthenticatedUser } from "../auth/session.guard.js";
import { SportsActiveCatalog } from "./sports-active-catalog.js";

class OnboardingAnswersRequestDto extends createZodDto(onboardingAnswersRequestSchema) {}

/** `PUT /v1/me/onboarding-answers` (ADR-035 §4, §5): the Onboarding answers become the profile. */
@Controller("me/onboarding-answers")
@UseGuards(SessionGuard)
export class OnboardingAnswersController {
  constructor(
    private readonly usersService: UsersService,
    private readonly sportCatalog: SportsActiveCatalog,
  ) {}

  /**
   * Fills only what the profile leaves empty, sports only if the athlete has
   * none: `204` for every valid request, even when nothing is written. `422`
   * for invalid answers, an age under 15, or an unknown or inactive sport.
   */
  @Put()
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiResponse({ status: 204, description: "Answers received" })
  submit(@Body() body: OnboardingAnswersRequestDto, @CurrentUser() user: AuthenticatedUser): Promise<void> {
    return this.usersService.submitOnboardingAnswers(user.userId, body, this.sportCatalog);
  }
}
