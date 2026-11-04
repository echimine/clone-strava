import { Inject, Injectable } from "@nestjs/common";
import {
  DeleteObjectCommand,
  DeleteObjectsCommand,
  GetObjectCommand,
  HeadObjectCommand,
  ListObjectsV2Command,
  NotFound,
  PutObjectCommand,
  type S3Client,
} from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { S3_CLIENT, STORAGE_OPTIONS, type StorageModuleOptions } from "./storage.constants.js";

/** A pre-signed URL and when it stops working. */
export interface PresignedUrl {
  url: string;
  expiresAt: Date;
}

/** An object found by {@link StorageService.listKeys}. */
export interface ListedObject {
  key: string;
  lastModified: Date;
}

/** S3 caps a `DeleteObjects` request at 1,000 keys. */
const DELETE_BATCH_SIZE = 1000;

/** Thrown by {@link StorageService.deleteObjects} with the keys the bucket did not delete. */
export class ObjectsNotDeletedError extends Error {
  constructor(readonly keys: string[]) {
    super(`${keys.length} object(s) not deleted, e.g. ${keys.slice(0, 3).join(", ")}`);
  }
}

/** Thrown by {@link StorageService.getObject} when the object is larger than allowed. */
export class ObjectTooLargeError extends Error {
  constructor(
    readonly key: string,
    readonly maxBytes: number,
  ) {
    super(`Object ${key} is larger than ${maxBytes} bytes`);
  }
}

/**
 * `storage` platform module (ADR-021 §1, ADR-009 "Bucket"): owns no
 * table, no business rule, wraps the OVH Object Storage bucket (S3
 * compatible) behind pre-signed URLs. Object keys follow the convention
 * `activities/{userId}/{activityId}/trace.json.gz` (ADR-009 §6, ADR-019
 * §1), built by the caller (`activities` module), not here.
 */
@Injectable()
export class StorageService {
  constructor(
    @Inject(S3_CLIENT) private readonly client: S3Client,
    @Inject(STORAGE_OPTIONS) private readonly options: StorageModuleOptions,
  ) {}

  /**
   * Pre-signed `PUT` (ADR-019 §1: 15 minutes by default). Without
   * `contentLength` only `host` is signed (the AWS presigner leaves
   * `Content-Type` out). With it, `Content-Type` and `Content-Length` are
   * signed too, so the bucket refuses a file of any other size or type
   * with `403 SignatureDoesNotMatch` (ADR-037 §2, §4); the client must send
   * both headers exactly.
   */
  async presignPut(
    key: string,
    contentType: string,
    options: { contentLength?: number; expiresInSeconds?: number } = {},
  ): Promise<PresignedUrl> {
    const { contentLength, expiresInSeconds = 900 } = options;
    const url = await getSignedUrl(
      this.client,
      new PutObjectCommand({
        Bucket: this.options.bucket,
        Key: key,
        ContentType: contentType,
        ContentLength: contentLength,
      }),
      {
        expiresIn: expiresInSeconds,
        ...(contentLength === undefined
          ? {}
          : { signableHeaders: new Set(["content-type", "content-length"]) }),
      },
    );
    return { url, expiresAt: new Date(Date.now() + expiresInSeconds * 1000) };
  }

  /** Pre-signed `GET`, for private media the owner or an authorized viewer may fetch. */
  async presignGet(key: string, expiresInSeconds = 900): Promise<PresignedUrl> {
    const url = await getSignedUrl(
      this.client,
      new GetObjectCommand({ Bucket: this.options.bucket, Key: key }),
      { expiresIn: expiresInSeconds },
    );
    return { url, expiresAt: new Date(Date.now() + expiresInSeconds * 1000) };
  }

  /** `HEAD` (ADR-019 §4, ADR-037 §4): the object's size, or `undefined` if it does not exist. */
  async headObject(key: string): Promise<{ sizeBytes: number } | undefined> {
    try {
      const output = await this.client.send(
        new HeadObjectCommand({ Bucket: this.options.bucket, Key: key }),
      );
      return { sizeBytes: output.ContentLength ?? 0 };
    } catch (error) {
      if (error instanceof NotFound || isNotFound(error)) {
        return undefined;
      }
      throw error;
    }
  }

  /**
   * Downloads a whole object, cut off at `maxBytes` (ADR-028 §4 step 2):
   * the stream is aborted as soon as the limit is crossed, so an oversized
   * object never ends up fully in memory. `undefined` if it does not exist.
   */
  async getObject(key: string, maxBytes: number): Promise<Uint8Array | undefined> {
    let output;
    try {
      output = await this.client.send(
        new GetObjectCommand({ Bucket: this.options.bucket, Key: key }),
      );
    } catch (error) {
      if (isNotFound(error)) {
        return undefined;
      }
      throw error;
    }
    if (output.ContentLength !== undefined && output.ContentLength > maxBytes) {
      output.Body?.transformToWebStream().cancel().catch(() => undefined);
      throw new ObjectTooLargeError(key, maxBytes);
    }

    const chunks: Uint8Array[] = [];
    let total = 0;
    const stream = output.Body?.transformToWebStream();
    if (!stream) {
      return new Uint8Array();
    }
    for await (const chunk of stream as AsyncIterable<Uint8Array>) {
      total += chunk.byteLength;
      if (total > maxBytes) {
        await stream.cancel().catch(() => undefined);
        throw new ObjectTooLargeError(key, maxBytes);
      }
      chunks.push(chunk);
    }
    return Buffer.concat(chunks, total);
  }

  /**
   * Ranged `GET` of bytes `start` to `end` included (ADR-037 §4: the file
   * signature). Shorter if the object is; empty for an empty object;
   * `undefined` if it does not exist.
   */
  async getObjectRange(
    key: string,
    range: { start: number; end: number },
  ): Promise<Uint8Array | undefined> {
    try {
      const output = await this.client.send(
        new GetObjectCommand({
          Bucket: this.options.bucket,
          Key: key,
          Range: `bytes=${range.start}-${range.end}`,
        }),
      );
      return (await output.Body?.transformToByteArray()) ?? new Uint8Array();
    } catch (error) {
      if (isNotFound(error)) {
        return undefined;
      }
      if (isInvalidRange(error)) {
        return new Uint8Array();
      }
      throw error;
    }
  }

  /** Every object under `prefix`, all `ListObjectsV2` pages walked (ADR-037 §11). */
  async listKeys(prefix: string): Promise<ListedObject[]> {
    const objects: ListedObject[] = [];
    let continuationToken: string | undefined;
    do {
      const output = await this.client.send(
        new ListObjectsV2Command({
          Bucket: this.options.bucket,
          Prefix: prefix,
          ContinuationToken: continuationToken,
        }),
      );
      for (const object of output.Contents ?? []) {
        if (object.Key !== undefined) {
          objects.push({ key: object.Key, lastModified: object.LastModified ?? new Date(0) });
        }
      }
      continuationToken = output.IsTruncated ? output.NextContinuationToken : undefined;
    } while (continuationToken);
    return objects;
  }

  /**
   * Deletes every object under `prefix` (a folder, ending with `/`), plus `alsoKeys` outside it,
   * in one go (ADR-037 §11). Throws like {@link deleteObjects}.
   */
  async deleteFolder(prefix: string, alsoKeys: readonly string[] = []): Promise<void> {
    const listed = await this.listKeys(prefix);
    await this.deleteObjects([...listed.map((object) => object.key), ...alsoKeys]);
  }

  /**
   * Deletes `keys` in `DeleteObjects` batches of 1,000 (ADR-037 §11);
   * missing keys succeed. Every batch is attempted, then
   * {@link ObjectsNotDeletedError} lists the keys the bucket refused.
   */
  async deleteObjects(keys: readonly string[]): Promise<void> {
    const failed: string[] = [];
    for (let from = 0; from < keys.length; from += DELETE_BATCH_SIZE) {
      const batch = keys.slice(from, from + DELETE_BATCH_SIZE);
      const output = await this.client.send(
        new DeleteObjectsCommand({
          Bucket: this.options.bucket,
          Delete: { Objects: batch.map((Key) => ({ Key })), Quiet: true },
        }),
      );
      for (const error of output.Errors ?? []) {
        failed.push(error.Key ?? "");
      }
    }
    if (failed.length > 0) {
      throw new ObjectsNotDeletedError(failed);
    }
  }

  /** Server-side `PUT`, e.g. the trace written by the worker for an imported activity (ADR-028 §4 step 9). */
  async putObject(
    key: string,
    body: Uint8Array,
    options: { contentType: string; contentEncoding?: string },
  ): Promise<void> {
    await this.client.send(
      new PutObjectCommand({
        Bucket: this.options.bucket,
        Key: key,
        Body: body,
        ContentType: options.contentType,
        ContentEncoding: options.contentEncoding,
      }),
    );
  }

  /** Deletes an object; deleting a missing key succeeds (S3 semantics). */
  async deleteObject(key: string): Promise<void> {
    await this.client.send(new DeleteObjectCommand({ Bucket: this.options.bucket, Key: key }));
  }
}

function isInvalidRange(error: unknown): boolean {
  if (typeof error !== "object" || error === null) {
    return false;
  }
  const { name, $metadata } = error as { name?: string; $metadata?: { httpStatusCode?: number } };
  return name === "InvalidRange" || $metadata?.httpStatusCode === 416;
}

function isNotFound(error: unknown): boolean {
  if (typeof error !== "object" || error === null) {
    return false;
  }
  const { name, $metadata } = error as { name?: string; $metadata?: { httpStatusCode?: number } };
  return name === "NotFound" || name === "NoSuchKey" || $metadata?.httpStatusCode === 404;
}
