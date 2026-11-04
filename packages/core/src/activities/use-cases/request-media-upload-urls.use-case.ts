import { Injectable } from "@nestjs/common";
import {
  ACTIVITY_MEDIA_MAX,
  MEDIA_UPLOAD_URL_EXPIRES_IN_SECONDS,
  activityMediaKey,
  type MediaUploadUrlsRequest,
  type MediaUploadUrlsResponse,
} from "@repo/contracts";
import { StorageService } from "../../storage/index.js";
import { ActivityMediaRepository } from "../repositories/activity-media.repository.js";
import { AuthorActivityResolver } from "../services/author-activity-resolver.js";
import { mediaLimitReached } from "../services/media-errors.js";

/**
 * `POST /v1/activities/:id/media/upload-urls` (ADR-037 §4): a 24-hour pre-signed `PUT` per file
 * of the Media's folder, `Content-Type` and `Content-Length` signed. Writes nothing, so the phone
 * replays it to renew a URL after a `403` from the bucket.
 */
@Injectable()
export class RequestMediaUploadUrlsUseCase {
  constructor(
    private readonly authorActivity: AuthorActivityResolver,
    private readonly media: ActivityMediaRepository,
    private readonly storage: StorageService,
  ) {}

  async execute(
    userId: string,
    activityId: string,
    request: MediaUploadUrlsRequest,
  ): Promise<MediaUploadUrlsResponse> {
    const activity = await this.authorActivity.resolve(userId, activityId);
    if ((await this.media.countByActivity(activity.id)) >= ACTIVITY_MEDIA_MAX) {
      throw mediaLimitReached();
    }
    const files = await Promise.all(
      request.files.map(async (file) => {
        const upload = await this.storage.presignPut(
          activityMediaKey(activity.userId, activity.id, request.mediaId, file.name),
          file.contentType,
          { contentLength: file.contentLength, expiresInSeconds: MEDIA_UPLOAD_URL_EXPIRES_IN_SECONDS },
        );
        return { name: file.name, uploadUrl: upload.url, expiresAt: upload.expiresAt.toISOString() };
      }),
    );
    return { files };
  }
}
