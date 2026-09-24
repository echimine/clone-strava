import { Inject, Injectable, NotImplementedException } from "@nestjs/common";
import type { HeadObjectCommandOutput, S3Client } from "@aws-sdk/client-s3";
import { S3_CLIENT, STORAGE_OPTIONS, type StorageModuleOptions } from "./storage.constants.js";

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
  async presignPut(_key: string, _contentType: string, _expiresInSeconds = 900): Promise<string> {
    throw new NotImplementedException();
  }

  /** Pre-signed `GET`, for private media the owner or an authorized viewer may fetch. */
  async presignGet(_key: string, _expiresInSeconds = 900): Promise<string> {
    throw new NotImplementedException();
  }

  /** `HEAD` (ADR-019 §4): does the object exist, and what is its size. */
  async head(_key: string): Promise<HeadObjectCommandOutput> {
    throw new NotImplementedException();
  }
}
