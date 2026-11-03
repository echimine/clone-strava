import { Injectable } from "@nestjs/common";
import { MEDIA_FILES, type Media } from "@repo/contracts";
import { ActivitiesService, type ActivityMediaRecord } from "@repo/core/activities";
import { StorageService } from "@repo/core/storage";

/** Lifetime of a Media's pre-signed `GET` (ADR-037 §1). */
export const MEDIA_URL_TTL_SECONDS = 3600;

/**
 * The single Media assembly of the API (ADR-037 §7, §12): turns `activity_media` rows into the
 * response's Media, each file behind a 1-hour pre-signed `GET`, so the object key never leaves
 * the API. Used by the feed, profile Activities and detail; the upload API and the Gallery reuse
 * {@link sign}. Signing makes no network call.
 */
@Injectable()
export class MediaAssembler {
  constructor(
    private readonly activities: ActivitiesService,
    private readonly storage: StorageService,
  ) {}

  /**
   * The signed Media of each Activity with one batch read for all of them (ADR-021 §2 rule 6):
   * pass only Activities the viewer may see. Unknown ids get `[]`.
   */
  async forActivities(activityIds: string[]): Promise<(activityId: string) => Media[]> {
    const records = await this.activities.getMedia(activityIds);
    const signed = new Map(
      await Promise.all(
        [...records].map(
          async ([activityId, media]) => [activityId, await Promise.all(media.map((m) => this.sign(m)))] as const,
        ),
      ),
    );
    return (activityId) => signed.get(activityId) ?? [];
  }

  /** One Media with fresh URLs for its files (ADR-037 §3): `posterUrl` only for a video. */
  async sign(record: ActivityMediaRecord): Promise<Media> {
    const files = MEDIA_FILES[record.kind];
    const [url, posterUrl, thumbUrl] = await Promise.all([
      this.signFile(record, files.original),
      files.poster === null ? null : this.signFile(record, files.poster),
      this.signFile(record, files.thumb),
    ]);
    return {
      id: record.id,
      kind: record.kind,
      width: record.width,
      height: record.height,
      durationMs: record.kind === "video" ? record.durationMs : null,
      url,
      posterUrl,
      thumbUrl,
    };
  }

  private async signFile(record: ActivityMediaRecord, file: string): Promise<string> {
    return (await this.storage.presignGet(`${record.folderKey}${file}`, MEDIA_URL_TTL_SECONDS)).url;
  }
}
