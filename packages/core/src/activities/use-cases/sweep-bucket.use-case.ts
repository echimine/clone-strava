import { Injectable } from "@nestjs/common";
import {
  ACTIVITIES_BUCKET_PREFIX,
  IMPORTS_BUCKET_PREFIX,
  activityPrefix,
  importPrefix,
  parseActivityKey,
  parseImportKey,
  type ActivityKeyParts,
} from "@repo/contracts";
import { StorageService, staleFolderKeys, type ListedObject } from "../../storage/index.js";
import { BucketReferencesRepository } from "../repositories/bucket-references.repository.js";

type Parsed<T> = ListedObject & { parts: T };

/**
 * The `activities` part of the daily `bucket-sweep` (ADR-037 §11). Deletes, once their newest
 * object is more than 7 days old:
 * - an Activity folder `activities/{userId}/{activityId}/` with no `activity` row;
 * - a Media folder `activities/…/media/{mediaId}/` with no `activity_media` row;
 * - an import folder `imports/{userId}/{importId}/` with neither an import nor an Activity.
 *
 * Keys outside this layout are left alone. Returns the number of objects deleted.
 */
@Injectable()
export class SweepBucketUseCase {
  constructor(
    private readonly references: BucketReferencesRepository,
    private readonly storage: StorageService,
  ) {}

  async execute(now = new Date()): Promise<number> {
    const [activityKeys, importKeys] = await Promise.all([
      this.orphanActivityKeys(now),
      this.orphanImportKeys(now),
    ]);
    const keys = [...activityKeys, ...importKeys];
    await this.storage.deleteObjects(keys);
    return keys.length;
  }

  private async orphanActivityKeys(now: Date): Promise<string[]> {
    const objects = parsed(await this.storage.listKeys(ACTIVITIES_BUCKET_PREFIX), parseActivityKey);
    const activities = await this.existingActivityPrefixes(objects.map((object) => object.parts.activityId));
    const ofActivity = (object: Parsed<ActivityKeyParts>) => activities.has(object.parts.activityPrefix);

    const withoutActivity = objects.filter((object) => !ofActivity(object));
    const mediaObjects = objects.filter(
      (object): object is Parsed<ActivityKeyParts & Required<Pick<ActivityKeyParts, "media">>> =>
        ofActivity(object) && object.parts.media !== undefined,
    );
    const media = await this.references.mediaActivities(unique(mediaObjects.map((object) => object.parts.media.mediaId)));
    const confirmed = new Set(media.map((row) => `${row.activityId}/${row.id}`));
    const withoutMedia = mediaObjects.filter(
      (object) => !confirmed.has(`${object.parts.activityId}/${object.parts.media.mediaId}`),
    );

    return [
      ...staleFolderKeys(withoutActivity, (object) => object.parts.activityPrefix, now),
      ...staleFolderKeys(withoutMedia, (object) => object.parts.media.prefix, now),
    ];
  }

  private async orphanImportKeys(now: Date): Promise<string[]> {
    const objects = parsed(await this.storage.listKeys(IMPORTS_BUCKET_PREFIX), parseImportKey);
    const ids = unique(objects.map((object) => object.parts.importId));
    const [imports, activities] = await Promise.all([
      this.references.importOwners(ids),
      this.existingActivityPrefixes(ids),
    ]);
    const referenced = new Set(imports.map((row) => importPrefix(row.userId, row.id)));
    const orphans = objects.filter(
      ({ parts }) =>
        !referenced.has(parts.prefix) && !activities.has(activityPrefix(parts.userId, parts.importId)),
    );
    return staleFolderKeys(orphans, (object) => object.parts.prefix, now);
  }

  /** The folder of each existing Activity among `ids`, under its owner's prefix. */
  private async existingActivityPrefixes(ids: readonly string[]): Promise<Set<string>> {
    const rows = await this.references.activityOwners(unique(ids));
    return new Set(rows.map((row) => activityPrefix(row.userId, row.id)));
  }
}

function parsed<T>(objects: readonly ListedObject[], parse: (key: string) => T | undefined): Parsed<T>[] {
  return objects.flatMap((object) => {
    const parts = parse(object.key);
    return parts === undefined ? [] : [{ ...object, parts }];
  });
}

function unique(ids: readonly string[]): string[] {
  return [...new Set(ids)];
}
