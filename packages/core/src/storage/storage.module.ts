import { Module, type DynamicModule } from "@nestjs/common";
import { S3Client } from "@aws-sdk/client-s3";
import { S3_CLIENT, STORAGE_OPTIONS, type StorageModuleOptions } from "./storage.constants.js";
import { StorageService } from "./storage.service.js";

/**
 * `storage` platform module (ADR-021 §1): configurable on the OVH Object
 * Storage endpoint via the AWS SDK v3 (ADR-009 "Bucket"). Every domain
 * module and app may import it (ADR-021 §2).
 */
@Module({})
export class StorageModule {
  static forRoot(options: StorageModuleOptions): DynamicModule {
    return {
      module: StorageModule,
      // Global: every domain module may use it (ADR-021 §2), registered once by each app.
      global: true,
      providers: [
        { provide: STORAGE_OPTIONS, useValue: options },
        {
          provide: S3_CLIENT,
          useFactory: (opts: StorageModuleOptions) =>
            new S3Client({
              endpoint: opts.endpoint,
              region: opts.region,
              credentials: {
                accessKeyId: opts.accessKeyId,
                secretAccessKey: opts.secretAccessKey,
              },
              // OVH Object Storage is S3-compatible but path-style: virtual-hosted
              // bucket URLs are not supported the same way as AWS S3 (ADR-009).
              forcePathStyle: true,
            }),
          inject: [STORAGE_OPTIONS],
        },
        StorageService,
      ],
      exports: [StorageService],
    };
  }
}
