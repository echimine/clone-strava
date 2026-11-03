import { Body, Controller, Patch, UseGuards } from "@nestjs/common";
import { createZodDto, ZodResponse } from "nestjs-zod";
import {
  updateProfileRequestSchema,
  updateProfileResponseSchema,
  type UpdateProfileResponse,
} from "@repo/contracts";
import { AuthService } from "@repo/core/auth";
import { UsersService } from "@repo/core/users";
import { CurrentUser } from "../auth/current-user.decorator.js";
import { SessionGuard, type AuthenticatedUser } from "../auth/session.guard.js";
import { AthleteIdentities } from "../identities/athlete-identities.js";

class UpdateProfileRequestDto extends createZodDto(updateProfileRequestSchema) {}
class UpdateProfileResponseDto extends createZodDto(updateProfileResponseSchema) {}

/** `PATCH /v1/me/profile` (ADR-036 §3): "Modifier le profil". */
@Controller("me/profile")
@UseGuards(SessionGuard)
export class MeProfileController {
  constructor(
    private readonly users: UsersService,
    private readonly auth: AuthService,
    private readonly identities: AthleteIdentities,
  ) {}

  /**
   * Sets the name everyone sees (`user_profile`), then Better Auth's `user.name` to "Prénom Nom".
   * Both modules are layer 0, so the two writes are composed here. Each name is trimmed, 1–50
   * characters (`422 validation_error`).
   */
  @Patch()
  @ZodResponse({ status: 200, type: UpdateProfileResponseDto })
  async update(
    @Body() body: UpdateProfileRequestDto,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<UpdateProfileResponse> {
    await this.users.updateName(user.userId, { firstName: body.firstName, lastName: body.lastName });
    await this.auth.setName(user.userId, `${body.firstName} ${body.lastName}`);
    const identity = await this.identities.resolve([user.userId]);
    return { athlete: identity(user.userId) };
  }
}
