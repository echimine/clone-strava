import { Inject, Injectable } from "@nestjs/common";
import {
  DeleteObjectCommand,
  GetObjectCommand,
  HeadObjectCommand,
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

  /** Pre-signed `PUT` (ADR-019 §1: 15 minutes, enforced content type). */
  async presignPut(key: string, contentType: string, expiresInSeconds = 900): Promise<PresignedUrl> {
    const url = await getSignedUrl(
      this.client,
      new PutObjectCommand({ Bucket: this.options.bucket, Key: key, ContentType: contentType }),
      { expiresIn: expiresInSeconds },
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

  /** `HEAD` (ADR-019 §4): the object's size, or `undefined` if it does not exist. */
  async head(key: string): Promise<{ sizeBytes: number } | undefined> {
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

function isNotFound(error: unknown): boolean {
  if (typeof error !== "object" || error === null) {
    return false;
  }
  const { name, $metadata } = error as { name?: string; $metadata?: { httpStatusCode?: number } };
  return name === "NotFound" || name === "NoSuchKey" || $metadata?.httpStatusCode === 404;
}
