import { Body, Controller, Get, Patch, UseGuards } from "@nestjs/common";
import { createZodDto, ZodResponse } from "nestjs-zod";
import {
  editableProfileResponseSchema,
  type EditableProfileResponse,
  updateProfileRequestSchema,
  updateProfileResponseSchema,
  type UpdateProfileResponse,
} from "@repo/contracts";
import { AuthService } from "@repo/core/auth";
import { UsersService } from "@repo/core/users";
import { CurrentUser } from "../auth/current-user.decorator.js";
import { SessionGuard, type AuthenticatedUser } from "../auth/session.guard.js";
import { AthleteIdentities } from "../identities/athlete-identities.js";
import { SportsActiveCatalog } from "../me/sports-active-catalog.js";

class UpdateProfileRequestDto extends createZodDto(updateProfileRequestSchema) {}
class UpdateProfileResponseDto extends createZodDto(updateProfileResponseSchema) {}
class EditableProfileResponseDto extends createZodDto(editableProfileResponseSchema) {}

/** `GET` and `PATCH /v1/me/profile` (ADR-036 §3): "Modifier le profil". */
@Controller("me/profile")
@UseGuards(SessionGuard)
export class MeProfileController {
  constructor(
    private readonly users: UsersService,
    private readonly auth: AuthService,
    private readonly identities: AthleteIdentities,
    private readonly sportCatalog: SportsActiveCatalog,
  ) {}

  /** The fields the screen starts from, private ones included: only for the athlete themself. */
  @Get()
  @ZodResponse({ status: 200, type: EditableProfileResponseDto })
  async get(@CurrentUser() user: AuthenticatedUser): Promise<EditableProfileResponse> {
    return { profile: await this.users.getEditableProfile(user.userId) };
  }

  /**
   * Writes the profile (`user_profile`, Practiced sports), then Better Auth's `user.name` to
   * "Prénom Nom". Both modules are layer 0, so the two writes are composed here. Each name is
   * trimmed, 1–50 characters; `422 validation_error` for any invalid field, an age under 15 or an
   * unknown or inactive sport.
   */
  @Patch()
  @ZodResponse({ status: 200, type: UpdateProfileResponseDto })
  async update(
    @Body() body: UpdateProfileRequestDto,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<UpdateProfileResponse> {
    await this.users.updateProfile(user.userId, body, this.sportCatalog);
    await this.auth.setName(user.userId, `${body.firstName} ${body.lastName}`);
    const identity = await this.identities.resolve([user.userId]);
    return { athlete: identity(user.userId) };
  }
}
