import { randomUUID } from "node:crypto";
import {
  ObjectTooLargeError,
  type ListedObject,
  type PresignedUrl,
  type StorageService,
} from "@repo/core/storage";

/**
 * In-memory bucket: S3 is the only third-party service faked here
 * (ADR-024 §2). Same behaviour as the worker's double
 * (`apps/worker/src/testing/test-worker-app.ts`).
 *
 * - `objects` holds the bucket; tests put and read bytes in it directly.
 * - `lastModified` backdates an object (default: now), for the sweep's 7 days.
 * - `failDeletes` makes every delete throw, like an unreachable bucket.
 * - Pre-signed URLs are `https://bucket.test/{key}?…`, with `X-Amz-Expires`
 *   and, when signed, `Content-Length`, so tests can read them back.
 */
export class InMemoryStorage implements Pick<StorageService, keyof StorageService> {
  readonly objects = new Map<string, Uint8Array>();
  readonly lastModified = new Map<string, Date>();
  failDeletes = false;

  async presignPut(
    key: string,
    _contentType: string,
    options: { contentLength?: number; expiresInSeconds?: number } = {},
  ): Promise<PresignedUrl> {
    const { contentLength, expiresInSeconds = 900 } = options;
    const url = presignedUrl(key, expiresInSeconds);
    if (contentLength !== undefined) {
      url.searchParams.set("Content-Length", String(contentLength));
    }
    return { url: url.toString(), expiresAt: new Date(Date.now() + expiresInSeconds * 1000) };
  }

  async presignGet(key: string, expiresInSeconds = 900): Promise<PresignedUrl> {
    return {
      url: presignedUrl(key, expiresInSeconds).toString(),
      expiresAt: new Date(Date.now() + expiresInSeconds * 1000),
    };
  }

  async headObject(key: string): Promise<{ sizeBytes: number } | undefined> {
    const object = this.objects.get(key);
    return object ? { sizeBytes: object.byteLength } : undefined;
  }

  async getObject(key: string, maxBytes: number): Promise<Uint8Array | undefined> {
    const object = this.objects.get(key);
    if (object && object.byteLength > maxBytes) {
      throw new ObjectTooLargeError(key, maxBytes);
    }
    return object;
  }

  async getObjectRange(
    key: string,
    range: { start: number; end: number },
  ): Promise<Uint8Array | undefined> {
    return this.objects.get(key)?.slice(range.start, range.end + 1);
  }

  async listKeys(prefix: string): Promise<ListedObject[]> {
    return [...this.objects.keys()]
      .filter((key) => key.startsWith(prefix))
      .map((key) => ({ key, lastModified: this.lastModified.get(key) ?? new Date() }));
  }

  async deleteFolder(prefix: string, alsoKeys: readonly string[] = []): Promise<void> {
    const listed = await this.listKeys(prefix);
    this.deleteObjectsNow([...listed.map((object) => object.key), ...alsoKeys]);
  }

  async putObject(key: string, body: Uint8Array): Promise<void> {
    this.objects.set(key, body);
  }

  async deleteObject(key: string): Promise<void> {
    this.deleteObjectsNow([key]);
  }

  async deleteObjects(keys: readonly string[]): Promise<void> {
    this.deleteObjectsNow(keys);
  }

  private deleteObjectsNow(keys: readonly string[]): void {
    if (this.failDeletes) {
      throw new Error("bucket unreachable");
    }
    for (const key of keys) {
      this.objects.delete(key);
      this.lastModified.delete(key);
    }
  }
}

function presignedUrl(key: string, expiresInSeconds: number): URL {
  const url = new URL(`https://bucket.test/${key}`);
  url.searchParams.set("X-Amz-Expires", String(expiresInSeconds));
  url.searchParams.set("X-Amz-Signature", randomUUID());
  return url;
}
