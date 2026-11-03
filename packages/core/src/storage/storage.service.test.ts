import {
  DeleteObjectsCommand,
  GetObjectCommand,
  HeadObjectCommand,
  ListObjectsV2Command,
  S3Client,
} from "@aws-sdk/client-s3";
import { describe, expect, it } from "vitest";
import type { StorageModuleOptions } from "./storage.constants.js";
import { StorageService } from "./storage.service.js";

const OPTIONS: StorageModuleOptions = {
  endpoint: "https://s3.gra.io.cloud.ovh.net",
  region: "gra",
  bucket: "assets",
  accessKeyId: "test",
  secretAccessKey: "test",
};

/** S3 caps a `ListObjectsV2` page and a `DeleteObjects` request at 1,000 keys. */
const S3_MAX_KEYS = 1000;

function s3Error(name: string, status: number): Error {
  return Object.assign(new Error(name), { name, $metadata: { httpStatusCode: status } });
}

/**
 * A bucket behind the S3 client's `send`, with S3's own limits: lists come
 * in pages of at most 1,000 keys, and a delete of more than 1,000 keys is
 * refused (`MalformedXML`).
 */
class FakeBucket {
  readonly objects = new Map<string, { body: Uint8Array; lastModified: Date }>();

  put(key: string, body: Uint8Array = new Uint8Array(1), lastModified = new Date()): void {
    this.objects.set(key, { body, lastModified });
  }

  async send(command: unknown): Promise<unknown> {
    if (command instanceof HeadObjectCommand) {
      const object = this.objects.get(command.input.Key!);
      if (!object) throw s3Error("NotFound", 404);
      return { ContentLength: object.body.byteLength };
    }
    if (command instanceof GetObjectCommand) {
      const object = this.objects.get(command.input.Key!);
      if (!object) throw s3Error("NoSuchKey", 404);
      const [, start, end] = /^bytes=(\d+)-(\d+)$/.exec(command.input.Range ?? "")!;
      if (Number(start) >= object.body.byteLength) throw s3Error("InvalidRange", 416);
      const bytes = object.body.slice(Number(start), Number(end) + 1);
      return { ContentLength: bytes.byteLength, Body: { transformToByteArray: async () => bytes } };
    }
    if (command instanceof ListObjectsV2Command) {
      const keys = [...this.objects.keys()]
        .filter((key) => key.startsWith(command.input.Prefix ?? ""))
        .sort();
      const from = command.input.ContinuationToken ? Number(command.input.ContinuationToken) : 0;
      const page = keys.slice(from, from + Math.min(command.input.MaxKeys ?? S3_MAX_KEYS, S3_MAX_KEYS));
      const next = from + page.length;
      return {
        Contents: page.map((key) => ({
          Key: key,
          Size: this.objects.get(key)!.body.byteLength,
          LastModified: this.objects.get(key)!.lastModified,
        })),
        IsTruncated: next < keys.length,
        NextContinuationToken: next < keys.length ? String(next) : undefined,
      };
    }
    if (command instanceof DeleteObjectsCommand) {
      const keys = command.input.Delete!.Objects!.map((object) => object.Key!);
      if (keys.length > S3_MAX_KEYS) throw s3Error("MalformedXML", 400);
      for (const key of keys) this.objects.delete(key);
      return { Deleted: keys.map((Key) => ({ Key })) };
    }
    throw new Error(`Unexpected command ${String(command)}`);
  }
}

function storageOn(bucket: FakeBucket): StorageService {
  return new StorageService(bucket as unknown as S3Client, OPTIONS);
}

describe("StorageService.presignPut", () => {
  const storage = new StorageService(
    new S3Client({
      endpoint: OPTIONS.endpoint,
      region: OPTIONS.region,
      credentials: { accessKeyId: "test", secretAccessKey: "test" },
      forcePathStyle: true,
    }),
    OPTIONS,
  );

  it("signs the size, so the bucket refuses a heavier file (ADR-037 §4)", async () => {
    const { url } = await storage.presignPut("avatars/u/a.jpg", "image/jpeg", { contentLength: 1_000_000 });

    const signed = new URL(url).searchParams.get("X-Amz-SignedHeaders")?.split(";");
    expect(signed).toEqual(expect.arrayContaining(["content-length", "content-type", "host"]));
  });

  it("leaves the size free when none is given, as for traces and imports", async () => {
    const { url } = await storage.presignPut("activities/u/a/trace.json.gz", "application/gzip");

    expect(new URL(url).searchParams.get("X-Amz-SignedHeaders")?.split(";")).not.toContain("content-length");
  });

  it("expires after the requested lifetime", async () => {
    const before = Date.now();
    const { url, expiresAt } = await storage.presignPut("k", "image/jpeg", { expiresInSeconds: 86_400 });

    expect(new URL(url).searchParams.get("X-Amz-Expires")).toBe("86400");
    expect(expiresAt.getTime()).toBeGreaterThanOrEqual(before + 86_400_000);
  });
});

describe("StorageService.headObject", () => {
  it("gives the size of an object, nothing for a missing one", async () => {
    const bucket = new FakeBucket();
    bucket.put("media/original.jpg", new Uint8Array(42));

    expect(await storageOn(bucket).headObject("media/original.jpg")).toEqual({ sizeBytes: 42 });
    expect(await storageOn(bucket).headObject("media/thumb.jpg")).toBeUndefined();
  });
});

describe("StorageService.getObjectRange", () => {
  it("reads only the requested bytes, end included", async () => {
    const bucket = new FakeBucket();
    bucket.put("photo.jpg", Uint8Array.from({ length: 100 }, (_, i) => i));

    expect(await storageOn(bucket).getObjectRange("photo.jpg", { start: 0, end: 15 })).toEqual(
      Uint8Array.from({ length: 16 }, (_, i) => i),
    );
  });

  it("returns what exists of a shorter object, nothing of an empty or missing one", async () => {
    const bucket = new FakeBucket();
    bucket.put("short.jpg", Uint8Array.of(0xff, 0xd8, 0xff));
    bucket.put("empty.jpg", new Uint8Array());

    const storage = storageOn(bucket);
    expect(await storage.getObjectRange("short.jpg", { start: 0, end: 15 })).toEqual(Uint8Array.of(0xff, 0xd8, 0xff));
    expect(await storage.getObjectRange("empty.jpg", { start: 0, end: 15 })).toEqual(new Uint8Array());
    expect(await storage.getObjectRange("missing.jpg", { start: 0, end: 15 })).toBeUndefined();
  });
});

describe("StorageService.listKeys", () => {
  it("walks every page under the prefix, with each object's size and date (ADR-037 §11)", async () => {
    const bucket = new FakeBucket();
    const keys = Array.from({ length: 2500 }, (_, i) => `activities/u/a/media/${String(i).padStart(4, "0")}`);
    for (const key of keys) bucket.put(key);
    bucket.put("activities/u/other/trace.json.gz");
    const lastModified = new Date("2026-10-01T00:00:00Z");
    bucket.put("activities/u/a/trace.json.gz", new Uint8Array(7), lastModified);

    const listed = await storageOn(bucket).listKeys("activities/u/a/");

    expect(listed.map((object) => object.key).sort()).toEqual([...keys, "activities/u/a/trace.json.gz"].sort());
    expect(listed.find((object) => object.key === "activities/u/a/trace.json.gz")).toEqual({
      key: "activities/u/a/trace.json.gz",
      sizeBytes: 7,
      lastModified,
    });
  });

  it("finds nothing under an empty prefix", async () => {
    expect(await storageOn(new FakeBucket()).listKeys("activities/u/none/")).toEqual([]);
  });
});

describe("StorageService.deleteObjects", () => {
  it("deletes more than 1,000 keys in batches the bucket accepts (ADR-037 §11)", async () => {
    const bucket = new FakeBucket();
    const keys = Array.from({ length: 2001 }, (_, i) => `activities/u/a/${i}`);
    for (const key of keys) bucket.put(key);
    bucket.put("activities/u/b/trace.json.gz");

    await storageOn(bucket).deleteObjects(keys);

    expect([...bucket.objects.keys()]).toEqual(["activities/u/b/trace.json.gz"]);
  });

  it("does nothing for no keys", async () => {
    await expect(storageOn(new FakeBucket()).deleteObjects([])).resolves.toBeUndefined();
  });
});
