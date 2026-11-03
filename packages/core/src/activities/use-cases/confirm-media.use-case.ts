import { ConflictException, Inject, Injectable } from "@nestjs/common";
import {
  ACTIVITY_MEDIA_MAX,
  MEDIA_FILE_SPECS,
  activityMediaPrefix,
  type ConfirmMediaRequest,
  type MediaFileSpec,
  type MediaKind,
} from "@repo/contracts";
import { DATABASE, type Database } from "../../infrastructure/index.js";
import { StorageService } from "../../storage/index.js";
import type { ActivityMediaRecord } from "../domain/activity-media.js";
import { MEDIA_SIGNATURE_BYTES, hasMediaFileSignature } from "../domain/media-file-signature.js";
import { ActivityMediaRepository } from "../repositories/activity-media.repository.js";
import { ActivityRepository } from "../repositories/activity.repository.js";
import { activityNotFound } from "../services/activity-not-found.js";
import { AuthorActivityResolver } from "../services/author-activity-resolver.js";
import { mediaLimitReached, mediaMissing } from "../services/media-errors.js";

export interface ConfirmMediaResult {
  /** `false` for a replay of a Media already confirmed. */
  created: boolean;
  media: ActivityMediaRecord;
}

/**
 * `POST /v1/activities/:id/media` (ADR-037 §4): every file of the Media is in the bucket with the
 * right size and signature, then the row is inserted, idempotent on `id`. A row exists only once
 * the Media is ready, so no read filters on a state.
 */
@Injectable()
export class ConfirmMediaUseCase {
  constructor(
    @Inject(DATABASE) private readonly db: Database,
    private readonly authorActivity: AuthorActivityResolver,
    private readonly activities: ActivityRepository,
    private readonly media: ActivityMediaRepository,
    private readonly storage: StorageService,
  ) {}

  async execute(userId: string, activityId: string, request: ConfirmMediaRequest): Promise<ConfirmMediaResult> {
    const activity = await this.authorActivity.resolve(userId, activityId);
    const existing = await this.media.findById(request.id);
    if (existing) {
      return replayed(existing, activity.id);
    }
    // Before the bucket calls; checked again under the lock below.
    if ((await this.media.countByActivity(activity.id)) >= ACTIVITY_MEDIA_MAX) {
      throw mediaLimitReached();
    }
    const folderKey = activityMediaPrefix(activity.userId, activity.id, request.id);
    await this.verifyFiles(folderKey, request.kind);

    const inserted = await this.db.transaction(async (tx) => {
      // Locking the Activity serialises its confirmations: two cannot both take the 8th place.
      if (!(await this.activities.findForUpdate(activity.id, tx))) {
        throw activityNotFound();
      }
      if ((await this.media.countByActivity(activity.id, tx)) >= ACTIVITY_MEDIA_MAX) {
        throw mediaLimitReached();
      }
      return this.media.insertIfAbsent(
        {
          id: request.id,
          activityId: activity.id,
          s3Key: folderKey,
          kind: request.kind,
          width: request.width,
          height: request.height,
          durationMs: request.durationMs ?? null,
          position: request.position,
        },
        tx,
      );
    });
    if (inserted) {
      return { created: true, media: inserted };
    }
    // A concurrent replay inserted it first.
    const row = await this.media.findById(request.id);
    if (!row) {
      throw activityNotFound();
    }
    return replayed(row, activity.id);
  }

  /** `409 media_missing` when a file is absent, `409 media_invalid` when too large or not of its type. */
  private async verifyFiles(folderKey: string, kind: MediaKind): Promise<void> {
    const specs: readonly MediaFileSpec[] = MEDIA_FILE_SPECS[kind];
    const objects = await Promise.all(specs.map((spec) => this.storage.headObject(`${folderKey}${spec.name}`)));
    if (objects.some((object) => object === undefined)) {
      throw mediaMissing();
    }
    const valid = await Promise.all(
      specs.map(async (spec, index) => {
        if (objects[index]!.sizeBytes > spec.maxBytes) {
          return false;
        }
        const head = await this.storage.getObjectRange(`${folderKey}${spec.name}`, {
          start: 0,
          end: MEDIA_SIGNATURE_BYTES - 1,
        });
        if (head === undefined) {
          return undefined;
        }
        return hasMediaFileSignature(spec.contentType, head);
      }),
    );
    if (valid.includes(undefined)) {
      // Removed between the HEAD and the read (bucket-sweep).
      throw mediaMissing();
    }
    if (valid.includes(false)) {
      throw new ConflictException({
        code: "media_invalid",
        message: "A file of the Media is too large or not of its type",
      });
    }
  }
}

/** A replay answers with the Media already confirmed; its id on another Activity is a conflict. */
function replayed(existing: ActivityMediaRecord, activityId: string): ConfirmMediaResult {
  if (existing.activityId !== activityId) {
    throw new ConflictException({ code: "media_id_taken", message: "This Media id belongs to another activity" });
  }
  return { created: false, media: existing };
}
