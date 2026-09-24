export interface StorageModuleOptions {
  endpoint: string;
  region: string;
  bucket: string;
  accessKeyId: string;
  secretAccessKey: string;
}

export const STORAGE_OPTIONS = Symbol("STORAGE_OPTIONS");
export const S3_CLIENT = Symbol("S3_CLIENT");
