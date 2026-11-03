import { randomUUID } from "node:crypto";
import { Injectable } from "@nestjs/common";
import { AVATAR_CONTENT_TYPE, avatarKey } from "@repo/contracts";
import { StorageService, type PresignedUrl } from "../../storage/index.js";

/** A pre-signed `PUT` for a new Avatar object (ADR-037 §2). */
export interface AvatarUpload {
  avatarId: string;
  upload: PresignedUrl;
}

/**
 * `POST /v1/me/avatar/upload-url` (ADR-037 §2): a new `avatarId` every time (immutable keys,
 * §1), under the caller's own `avatars/{userId}/` folder, with a 15-minute `PUT` whose
 * `Content-Type: image/jpeg` and `Content-Length: sizeBytes` are signed.
 */
@Injectable()
export class RequestAvatarUploadUseCase {
  constructor(private readonly storage: StorageService) {}

  async execute(userId: string, sizeBytes: number): Promise<AvatarUpload> {
    const avatarId = randomUUID();
    const upload = await this.storage.presignPut(avatarKey(userId, avatarId), AVATAR_CONTENT_TYPE, {
      contentLength: sizeBytes,
    });
    return { avatarId, upload };
  }
}
