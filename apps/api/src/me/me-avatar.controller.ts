import { Body, Controller, Delete, HttpCode, HttpStatus, Post, Put, UseGuards } from "@nestjs/common";
import { ApiResponse } from "@nestjs/swagger";
import { createZodDto, ZodResponse } from "nestjs-zod";
import {
  avatarUploadUrlRequestSchema,
  avatarUploadUrlResponseSchema,
  setAvatarRequestSchema,
  setAvatarResponseSchema,
  type AvatarUploadUrlResponse,
  type SetAvatarResponse,
} from "@repo/contracts";
import { UsersService } from "@repo/core/users";
import { CurrentUser } from "../auth/current-user.decorator.js";
import { SessionGuard, type AuthenticatedUser } from "../auth/session.guard.js";
import { AthleteIdentities } from "../identities/athlete-identities.js";

class AvatarUploadUrlRequestDto extends createZodDto(avatarUploadUrlRequestSchema) {}
class AvatarUploadUrlResponseDto extends createZodDto(avatarUploadUrlResponseSchema) {}
class SetAvatarRequestDto extends createZodDto(setAvatarRequestSchema) {}
class SetAvatarResponseDto extends createZodDto(setAvatarResponseSchema) {}

/**
 * The athlete's Avatar (ADR-037 §2): ask for an upload URL, `PUT` the JPEG to the bucket, then
 * confirm it here. No offline queue: the phone needs the network for all three calls.
 */
@Controller("me/avatar")
@UseGuards(SessionGuard)
export class MeAvatarController {
  constructor(
    private readonly users: UsersService,
    private readonly identities: AthleteIdentities,
  ) {}

  /**
   * `201`: a new `avatarId` and a 15-minute pre-signed `PUT`. The phone sends exactly
   * `Content-Type: image/jpeg` and `Content-Length: {sizeBytes}` (both signed). `sizeBytes` is 1
   * byte to 1 MB, else `422 validation_error`.
   */
  @Post("upload-url")
  @ZodResponse({ status: 201, type: AvatarUploadUrlResponseDto })
  async requestUploadUrl(
    @Body() body: AvatarUploadUrlRequestDto,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<AvatarUploadUrlResponse> {
    const { avatarId, upload } = await this.users.requestAvatarUpload(user.userId, body.sizeBytes);
    return { avatarId, uploadUrl: upload.url, expiresAt: upload.expiresAt.toISOString() };
  }

  /**
   * The uploaded object becomes the Avatar (`HEAD` first), and the previous one is deleted:
   * `200` with the identity everyone now sees. `409 avatar_missing` when nothing was uploaded under
   * this `avatarId`, `409 avatar_too_large` over 1 MB. Replaying the same `avatarId` is harmless.
   */
  @Put()
  @ZodResponse({ status: 200, type: SetAvatarResponseDto })
  async set(@Body() body: SetAvatarRequestDto, @CurrentUser() user: AuthenticatedUser): Promise<SetAvatarResponse> {
    await this.users.setAvatar(user.userId, body.avatarId);
    const identity = await this.identities.resolve([user.userId]);
    return { athlete: identity(user.userId) };
  }

  /** Removes the Avatar and deletes its object: `204`, also without an Avatar. */
  @Delete()
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiResponse({ status: 204, description: "Avatar removed" })
  async remove(@CurrentUser() user: AuthenticatedUser): Promise<void> {
    await this.users.removeAvatar(user.userId);
  }
}
