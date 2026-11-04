import { randomUUID } from "node:crypto";
import { BullModule } from "@nestjs/bullmq";
import type { INestApplication } from "@nestjs/common";
import { APP_FILTER, APP_INTERCEPTOR, APP_PIPE } from "@nestjs/core";
import { EventEmitter2, EventEmitterModule } from "@nestjs/event-emitter";
import { Test } from "@nestjs/testing";
import { Redis } from "ioredis";
import { ZodSerializerInterceptor, ZodValidationPipe } from "nestjs-zod";
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { MEDIA_DELETED_EVENT, activityMediaKey, activityMediaPrefix } from "@repo/contracts";
import { ActivitiesModule } from "@repo/core/activities";
import { AnalyticsModule } from "@repo/core/analytics";
import { AuthService } from "@repo/core/auth";
import { EngagementModule } from "@repo/core/engagement";
import { GeocodingModule } from "@repo/core/geocoding";
import { CoreInfrastructureModule, DATABASE, type Database } from "@repo/core/infrastructure";
import { StorageModule, StorageService } from "@repo/core/storage";
import { UsersModule } from "@repo/core/users";
import { ensureTestDatabaseMigrated, TEST_DATABASE_URL, TEST_REDIS_URL } from "../auth/test-auth-app.js";
import { SessionGuard } from "../auth/session.guard.js";
import { GlobalExceptionFilter } from "../common/global-exception.filter.js";
import { MediaAssembler } from "../media/media-assembler.js";
import { listenOnLoopback } from "../testing/listen-on-loopback.js";
import { InMemoryStorage } from "../testing/in-memory-storage.js";
import { signedMediaUrl } from "../testing/signed-urls.js";
import { ActivityMediaController } from "./activity-media.controller.js";

/** In-memory bucket: S3 is the only third-party service faked here (ADR-024 §2). */
const storage = new InMemoryStorage();
const objects = storage.objects;

const MB = 1024 * 1024;
/** The first bytes of a JPEG (`FF D8 FF`) and of an MP4 (a `ftyp` box), padded to `size`. */
const jpeg = (size = 2048) => bytes([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46], size);
const mp4 = (size = 4096) =>
  bytes([0x00, 0x00, 0x00, 0x18, ...new TextEncoder().encode("ftypmp42"), 0x00, 0x00, 0x00, 0x00], size);
function bytes(head: number[], size: number): Uint8Array {
  const out = new Uint8Array(size);
  out.set(head);
  return out;
}

const photoFiles = [
  { name: "original.jpg", contentType: "image/jpeg", contentLength: 2 * MB },
  { name: "thumb.jpg", contentType: "image/jpeg", contentLength: 200_000 },
];
const videoFiles = [
  { name: "original.mp4", contentType: "video/mp4", contentLength: 40 * MB },
  { name: "poster.jpg", contentType: "image/jpeg", contentLength: 300_000 },
  { name: "thumb.jpg", contentType: "image/jpeg", contentLength: 100_000 },
];

/**
 * Media upload API (ADR-037 §3, §4) over real HTTP and Postgres (ADR-024 §2): upload URLs,
 * confirmation and deletion. Sessions come from `x-test-user` through a fake `AuthService`.
 */
describe("Media upload API /v1/activities/:id/media (integration)", () => {
  let app: INestApplication;
  let baseUrl: string;
  let bullConnection: Redis;
  const author = randomUUID();
  const other = randomUUID();

  async function sql(text: string, params: unknown[]) {
    return (await app.get<Database>(DATABASE).$client.query(text, params)).rows;
  }

  function call(path: string, user: string, init: { method?: string; body?: unknown } = {}) {
    return fetch(`${baseUrl}/v1/activities${path}`, {
      method: init.method ?? "POST",
      headers: { "content-type": "application/json", "x-test-user": user },
      body: init.body === undefined ? undefined : JSON.stringify(init.body),
    });
  }
  const errorCode = async (response: Response) =>
    ((await response.json()) as { error: { code: string } }).error.code;

  /** An Activity of `author`, `public`, in the given state (pending by default). */
  async function activity(status: "pending" | "processing" | "processed" | "failed" = "pending") {
    const id = randomUUID();
    await sql(
      `insert into activities.activity
         (id, user_id, sport_type_code, title, started_at, ended_at, visibility, processing_status)
       values ($1, $2, 'run', 'Course', now() - interval '1 hour', now() - interval '30 minutes',
               'public', $3)`,
      [id, author, status],
    );
    return id;
  }

  /** `count` photos already confirmed on the Activity, inserted as rows. Returns their ids in order. */
  async function confirmedMedia(activityId: string, count: number): Promise<string[]> {
    const ids: string[] = [];
    for (let position = 0; position < count; position++) {
      const id = randomUUID();
      await sql(
        `insert into activities.activity_media (id, activity_id, s3_key, kind, width, height, position)
         values ($1, $2, $3, 'photo', 2048, 1536, $4)`,
        [id, activityId, activityMediaPrefix(author, activityId, id), position],
      );
      ids.push(id);
    }
    return ids;
  }

  beforeAll(async () => {
    await ensureTestDatabaseMigrated();
    bullConnection = new Redis(TEST_REDIS_URL, { maxRetriesPerRequest: null });
    const moduleRef = await Test.createTestingModule({
      imports: [
        CoreInfrastructureModule.forRoot({ databaseUrl: TEST_DATABASE_URL, redisUrl: TEST_REDIS_URL }),
        BullModule.forRoot({ connection: bullConnection, prefix: `test-${randomUUID()}` }),
        AnalyticsModule.forRoot({}),
        StorageModule.forRoot({
          endpoint: "https://bucket.test",
          region: "test",
          bucket: "test",
          accessKeyId: "test",
          secretAccessKey: "test",
        }),
        GeocodingModule.forRoot({}),
        EventEmitterModule.forRoot({ wildcard: true, delimiter: "." }),
        ActivitiesModule,
        EngagementModule,
        UsersModule,
      ],
      controllers: [ActivityMediaController],
      providers: [
        SessionGuard,
        MediaAssembler,
        {
          provide: AuthService,
          useValue: {
            getSession: async (headers: Headers) => {
              const userId = headers.get("x-test-user");
              return userId
                ? { userId, email: `${userId}@test.local`, name: "Test", role: "user", twoFactorEnabled: false }
                : null;
            },
            getPublicIdentities: async () => [],
          },
        },
        { provide: APP_PIPE, useClass: ZodValidationPipe },
        { provide: APP_INTERCEPTOR, useClass: ZodSerializerInterceptor },
        { provide: APP_FILTER, useClass: GlobalExceptionFilter },
      ],
    })
      .overrideProvider(StorageService)
      .useValue(storage)
      .compile();

    app = moduleRef.createNestApplication();
    app.setGlobalPrefix("v1");
    baseUrl = await listenOnLoopback(app);

    for (const id of [author, other]) {
      await sql('insert into "user" (id, name, email) values ($1, $2, $3)', [id, "Test", `${id}@test.local`]);
    }
  }, 30_000);

  afterEach(() => {
    storage.failDeletes = false;
  });

  afterAll(async () => {
    // Cascades to the users' activities and their Media.
    await sql('delete from "user" where id = any($1)', [[author, other]]);
    await app?.close();
    await bullConnection?.quit();
  });

  describe("POST /:id/media/upload-urls", () => {
    const uploadUrls = (activityId: string, body: unknown, user = author) =>
      call(`/${activityId}/media/upload-urls`, user, { body });

    it("gives the author a 24-hour signed PUT per file under the Media's folder, whatever the state", async () => {
      const activityId = await activity("pending");
      const mediaId = randomUUID();

      const response = await uploadUrls(activityId, { mediaId, kind: "photo", files: photoFiles });

      expect(response.status).toBe(200);
      const body = (await response.json()) as { files: { name: string; uploadUrl: string; expiresAt: string }[] };
      expect(body.files.map((file) => file.name)).toEqual(["original.jpg", "thumb.jpg"]);
      const original = new URL(body.files[0]!.uploadUrl);
      expect(original.pathname).toBe(`/${activityMediaKey(author, activityId, mediaId, "original.jpg")}`);
      expect(original.searchParams.get("X-Amz-Expires")).toBe("86400");
      expect(original.searchParams.get("Content-Length")).toBe(String(2 * MB));
      expect(Date.parse(body.files[0]!.expiresAt) - Date.now()).toBeGreaterThan(23 * 3600 * 1000);
      // Nothing is written.
      expect(await sql("select 1 from activities.activity_media where id = $1", [mediaId])).toHaveLength(0);
      expect([...objects.keys()].some((key) => key.startsWith(activityMediaPrefix(author, activityId, mediaId)))).toBe(
        false,
      );
    });

    it("answers 403 not_activity_author to another athlete who sees it, 404 when hidden or unknown", async () => {
      const visible = await activity("processed");
      const hidden = await activity("pending");
      const body = { mediaId: randomUUID(), kind: "photo", files: photoFiles };

      const forbidden = await uploadUrls(visible, body, other);
      expect(forbidden.status).toBe(403);
      expect(await errorCode(forbidden)).toBe("not_activity_author");
      const notFound = await uploadUrls(hidden, body, other);
      expect(notFound.status).toBe(404);
      expect(await errorCode(notFound)).toBe("activity_not_found");
      expect((await uploadUrls(randomUUID(), body)).status).toBe(404);
    });

    it("gives a video its MP4, poster and thumbnail", async () => {
      const response = await uploadUrls(await activity("failed"), {
        mediaId: randomUUID(),
        kind: "video",
        files: videoFiles,
      });

      expect(response.status).toBe(200);
      const body = (await response.json()) as { files: { name: string }[] };
      expect(body.files.map((file) => file.name)).toEqual(["original.mp4", "poster.jpg", "thumb.jpg"]);
    });

    it.each([
      ["a video without poster", "video", videoFiles.filter((file) => file.name !== "poster.jpg")],
      ["a photo with an MP4", "photo", [...photoFiles, videoFiles[0]]],
      ["a file twice", "photo", [photoFiles[0], photoFiles[0]]],
      ["an original above 8 MB", "photo", [{ ...photoFiles[0], contentLength: 9 * MB }, photoFiles[1]]],
      ["a thumbnail above 1 MB", "video", [...videoFiles.slice(0, 2), { ...videoFiles[2], contentLength: 2 * MB }]],
      ["a JPEG sent as MP4", "photo", [{ ...photoFiles[0], contentType: "video/mp4" }, photoFiles[1]]],
      ["an unknown file", "photo", [photoFiles[0], { ...photoFiles[1], name: "exif.json" }]],
    ])("refuses %s (422)", async (_label, kind, files) => {
      const response = await uploadUrls(await activity(), { mediaId: randomUUID(), kind, files });

      expect(response.status).toBe(422);
      expect(await errorCode(response)).toBe("validation_error");
    });

    it("refuses a 9th Media (409 media_limit_reached)", async () => {
      const activityId = await activity("processed");
      await confirmedMedia(activityId, 8);

      const response = await uploadUrls(activityId, { mediaId: randomUUID(), kind: "photo", files: photoFiles });

      expect(response.status).toBe(409);
      expect(await errorCode(response)).toBe("media_limit_reached");
    });
  });

  describe("POST /:id/media", () => {
    const confirm = (activityId: string, body: unknown, user = author) => call(`/${activityId}/media`, user, { body });
    const photo = (id: string, position = 0) => ({ id, kind: "photo", width: 2048, height: 1536, durationMs: null, position });
    const video = (id: string, position = 0) => ({ id, kind: "video", width: 1280, height: 720, durationMs: 12_500, position });
    const put = (activityId: string, mediaId: string, files: Record<string, Uint8Array>) => {
      for (const [name, body] of Object.entries(files)) {
        objects.set(activityMediaKey(author, activityId, mediaId, name), body);
      }
    };
    const putPhoto = (activityId: string, mediaId: string) =>
      put(activityId, mediaId, { "original.jpg": jpeg(), "thumb.jpg": jpeg(512) });

    it("confirms a photo whose files are in the bucket (201), then replays it (200, same body)", async () => {
      const activityId = await activity("processing");
      const mediaId = randomUUID();
      putPhoto(activityId, mediaId);

      const first = await confirm(activityId, photo(mediaId, 3));

      expect(first.status).toBe(201);
      const created = ((await first.json()) as { media: Record<string, unknown> }).media;
      const folder = activityMediaPrefix(author, activityId, mediaId);
      // Each response signs its URLs anew: matched, never copied from another response.
      const expected = {
        id: mediaId,
        kind: "photo",
        width: 2048,
        height: 1536,
        durationMs: null,
        url: signedMediaUrl(folder, "original.jpg"),
        posterUrl: null,
        thumbUrl: signedMediaUrl(folder, "thumb.jpg"),
      };
      expect(created).toEqual(expected);
      expect(
        await sql("select position, s3_key from activities.activity_media where id = $1", [mediaId]),
      ).toEqual([{ position: 3, s3_key: activityMediaPrefix(author, activityId, mediaId) }]);

      const replay = await confirm(activityId, photo(mediaId, 3));

      expect(replay.status).toBe(200);
      expect(((await replay.json()) as { media: Record<string, unknown> }).media).toEqual(expected);
      expect(await sql("select 1 from activities.activity_media where id = $1", [mediaId])).toHaveLength(1);
    });

    it("confirms a photo sent without durationMs, as the generated Swift client encodes a nil", async () => {
      const activityId = await activity("processed");
      const mediaId = randomUUID();
      putPhoto(activityId, mediaId);
      const { durationMs: _omitted, ...body } = photo(mediaId);

      const response = await confirm(activityId, body);

      expect(response.status).toBe(201);
      expect(((await response.json()) as { media: { durationMs: unknown } }).media.durationMs).toBeNull();
    });

    it("confirms a video with its duration and poster", async () => {
      const activityId = await activity("processed");
      const mediaId = randomUUID();
      put(activityId, mediaId, { "original.mp4": mp4(), "poster.jpg": jpeg(), "thumb.jpg": jpeg(512) });

      const response = await confirm(activityId, video(mediaId));

      expect(response.status).toBe(201);
      const media = ((await response.json()) as { media: Record<string, unknown> }).media;
      expect(media).toMatchObject({ kind: "video", width: 1280, height: 720, durationMs: 12_500 });
      expect(media.url).toContain(`${mediaId}/original.mp4?`);
      expect(media.posterUrl).toContain(`${mediaId}/poster.jpg?`);
    });

    it("answers 409 media_missing when a file is not in the bucket, and inserts nothing", async () => {
      const activityId = await activity("processed");
      const nothingSent = randomUUID();
      const noThumb = randomUUID();
      put(activityId, noThumb, { "original.jpg": jpeg() });

      for (const mediaId of [nothingSent, noThumb]) {
        const response = await confirm(activityId, photo(mediaId));
        expect(response.status).toBe(409);
        expect(await errorCode(response)).toBe("media_missing");
      }
      expect(await sql("select 1 from activities.activity_media where activity_id = $1", [activityId])).toHaveLength(0);
    });

    it.each([
      ["a photo that is not a JPEG", "photo", { "original.jpg": mp4(), "thumb.jpg": jpeg(512) }],
      ["a thumbnail that is not a JPEG", "photo", { "original.jpg": jpeg(), "thumb.jpg": new Uint8Array(512) }],
      ["a video that is not an MP4", "video", { "original.mp4": jpeg(), "poster.jpg": jpeg(), "thumb.jpg": jpeg() }],
      ["an empty file", "photo", { "original.jpg": new Uint8Array(), "thumb.jpg": jpeg(512) }],
      ["a photo above 8 MB", "photo", { "original.jpg": jpeg(8 * MB + 1), "thumb.jpg": jpeg(512) }],
    ])("answers 409 media_invalid for %s", async (_label, kind, files) => {
      const activityId = await activity("processed");
      const mediaId = randomUUID();
      put(activityId, mediaId, files);

      const response = await confirm(activityId, kind === "photo" ? photo(mediaId) : video(mediaId));

      expect(response.status).toBe(409);
      expect(await errorCode(response)).toBe("media_invalid");
      expect(await sql("select 1 from activities.activity_media where id = $1", [mediaId])).toHaveLength(0);
    });

    it("refuses the 9th confirmation even when its upload URLs were obtained before (409 media_limit_reached)", async () => {
      const activityId = await activity("processed");
      await confirmedMedia(activityId, 7);
      const ninth = randomUUID();
      const urls = await call(`/${activityId}/media/upload-urls`, author, {
        body: { mediaId: ninth, kind: "photo", files: photoFiles },
      });
      expect(urls.status).toBe(200);
      const eighth = randomUUID();
      putPhoto(activityId, eighth);
      putPhoto(activityId, ninth);
      expect((await confirm(activityId, photo(eighth, 7))).status).toBe(201);

      const response = await confirm(activityId, photo(ninth, 7));

      expect(response.status).toBe(409);
      expect(await errorCode(response)).toBe("media_limit_reached");
      expect(await sql("select 1 from activities.activity_media where activity_id = $1", [activityId])).toHaveLength(8);
    });

    it("answers 403 not_activity_author to another athlete who sees it, 404 when hidden or unknown", async () => {
      const visible = await activity("processed");
      const hidden = await activity("pending");
      const mediaId = randomUUID();
      putPhoto(visible, mediaId);
      putPhoto(hidden, mediaId);

      const forbidden = await confirm(visible, photo(mediaId), other);
      expect(forbidden.status).toBe(403);
      expect(await errorCode(forbidden)).toBe("not_activity_author");
      expect((await confirm(hidden, photo(mediaId), other)).status).toBe(404);
      expect((await confirm(randomUUID(), photo(mediaId))).status).toBe(404);
      expect(await sql("select 1 from activities.activity_media where id = $1", [mediaId])).toHaveLength(0);
    });

    it.each([
      ["a photo with a duration", { ...photo(randomUUID()), durationMs: 1000 }],
      ["a video without duration", { ...video(randomUUID()), durationMs: null }],
      ["a position beyond the 8th", photo(randomUUID(), 8)],
    ])("refuses %s (422)", async (_label, body) => {
      const response = await confirm(await activity(), body);

      expect(response.status).toBe(422);
      expect(await errorCode(response)).toBe("validation_error");
    });
  });

  describe("DELETE /:id/media/:mediaId", () => {
    const remove = (activityId: string, mediaId: string, user = author) =>
      call(`/${activityId}/media/${mediaId}`, user, { method: "DELETE" });
    const mediaIds = async (activityId: string) =>
      (
        await sql("select id from activities.activity_media where activity_id = $1 order by position", [activityId])
      ).map((row: { id: string }) => row.id);
    const mediaFirst = async (activityId: string) =>
      ((await sql("select media_first from activities.activity where id = $1", [activityId]))[0] as {
        media_first: boolean;
      }).media_first;
    const filesOf = (activityId: string, mediaId: string) =>
      [...objects.keys()].filter((key) => key.startsWith(activityMediaPrefix(author, activityId, mediaId)));

    it("deletes the Media's row and folder (204), and keeps the others", async () => {
      const activityId = await activity("processed");
      const [first, second] = await confirmedMedia(activityId, 2);
      for (const mediaId of [first!, second!]) {
        objects.set(activityMediaKey(author, activityId, mediaId, "original.jpg"), jpeg());
        objects.set(activityMediaKey(author, activityId, mediaId, "thumb.jpg"), jpeg(512));
      }
      const emit = vi.spyOn(app.get(EventEmitter2), "emit");

      const response = await remove(activityId, second!);

      expect(response.status).toBe(204);
      expect(await mediaIds(activityId)).toEqual([first]);
      expect(filesOf(activityId, second!)).toEqual([]);
      expect(filesOf(activityId, first!)).toHaveLength(2);
      // Not a Sanction (ADR-038 §10): the author removed it.
      expect(emit).toHaveBeenCalledWith(MEDIA_DELETED_EVENT, {
        mediaId: second,
        activityId,
        userId: author,
        bySanction: false,
      });
      emit.mockRestore();
    });

    it("answers 204 for a Media already gone, and deletes the files of one never confirmed", async () => {
      const activityId = await activity("pending");
      const neverConfirmed = randomUUID();
      objects.set(activityMediaKey(author, activityId, neverConfirmed, "original.mp4"), mp4());
      const emit = vi.spyOn(app.get(EventEmitter2), "emit");

      expect((await remove(activityId, neverConfirmed)).status).toBe(204);
      expect(filesOf(activityId, neverConfirmed)).toEqual([]);
      expect((await remove(activityId, neverConfirmed)).status).toBe(204);
      expect(emit).not.toHaveBeenCalledWith(MEDIA_DELETED_EVENT, expect.anything());
      emit.mockRestore();
    });

    it("puts the map first again when the deleted Media was first", async () => {
      const activityId = await activity("processed");
      const [first, second, third] = await confirmedMedia(activityId, 3);
      await sql("update activities.activity set media_first = true where id = $1", [activityId]);

      expect((await remove(activityId, second!)).status).toBe(204);
      expect(await mediaFirst(activityId)).toBe(true);

      expect((await remove(activityId, first!)).status).toBe(204);
      expect(await mediaFirst(activityId)).toBe(false);
      expect(await mediaIds(activityId)).toEqual([third]);
    });

    it("still answers 204 when the bucket cannot delete the files", async () => {
      const activityId = await activity("processed");
      const [mediaId] = await confirmedMedia(activityId, 1);
      objects.set(activityMediaKey(author, activityId, mediaId!, "original.jpg"), jpeg());
      storage.failDeletes = true;

      expect((await remove(activityId, mediaId!)).status).toBe(204);
      expect(await mediaIds(activityId)).toEqual([]);
    });

    it("answers 403 not_activity_author to another athlete who sees it, 404 when hidden or unknown", async () => {
      const visible = await activity("processed");
      const hidden = await activity("pending");
      const [visibleMedia] = await confirmedMedia(visible, 1);
      const [hiddenMedia] = await confirmedMedia(hidden, 1);

      const forbidden = await remove(visible, visibleMedia!, other);
      expect(forbidden.status).toBe(403);
      expect(await errorCode(forbidden)).toBe("not_activity_author");
      expect((await remove(hidden, hiddenMedia!, other)).status).toBe(404);
      expect((await remove(randomUUID(), visibleMedia!)).status).toBe(404);
      expect(await mediaIds(visible)).toEqual([visibleMedia]);
      expect(await mediaIds(hidden)).toEqual([hiddenMedia]);
    });
  });
});
