import { z } from "zod";

/** Shared by the three backend apps (ADR-009 "Common foundation"). */
const logLevelSchema = z.enum(["fatal", "error", "warn", "info", "debug", "trace"]);

/** OVH Object Storage, via the AWS SDK v3 (ADR-009). */
const s3EnvShape = {
  S3_ENDPOINT: z.string().min(1),
  S3_REGION: z.string().min(1),
  S3_BUCKET: z.string().min(1),
  S3_ACCESS_KEY_ID: z.string().min(1),
  S3_SECRET_ACCESS_KEY: z.string().min(1),
};

/** `posthog-node`; optional so a dev environment can run without it (ADR-015). */
const postHogEnvShape = {
  POSTHOG_API_KEY: z.string().min(1).optional(),
  POSTHOG_HOST: z.string().min(1).optional(),
};

/** `apps/api` (ADR-009): the only entry point for mobile and backoffice clients. */
export const apiEnvSchema = z.object({
  DATABASE_URL: z.string().min(1),
  REDIS_URL: z.string().min(1),
  PORT: z.coerce.number().int().positive().default(3000),
  LOG_LEVEL: logLevelSchema.default("info"),
  BETTER_AUTH_SECRET: z.string().min(1),
  BETTER_AUTH_URL: z.string().min(1),
  REALTIME_TOKEN_SECRET: z.string().min(1),
  ...s3EnvShape,
  ...postHogEnvShape,
  REVENUECAT_WEBHOOK_SECRET: z.string().min(1),
  RESEND_API_KEY: z.string().min(1),
  RESEND_WEBHOOK_SECRET: z.string().min(1),
  GOOGLE_CLIENT_ID: z.string().min(1),
  GOOGLE_CLIENT_SECRET: z.string().min(1),
});
export type ApiEnv = z.infer<typeof apiEnvSchema>;

/** `apps/worker` (ADR-011): a NestJS application context, no HTTP server, so no `PORT`. */
export const workerEnvSchema = z.object({
  DATABASE_URL: z.string().min(1),
  REDIS_URL: z.string().min(1),
  LOG_LEVEL: logLevelSchema.default("info"),
  ...s3EnvShape,
  ...postHogEnvShape,
  REVENUECAT_API_KEY: z.string().min(1),
  // ADR-029: server-side Mapbox token for reverse geocoding; optional (no place name without it).
  MAPBOX_GEOCODING_TOKEN: z.string().min(1).optional(),
  // ADR-029: Mapbox's terms require the (billed) permanent endpoint to store results.
  MAPBOX_GEOCODING_PERMANENT: z.stringbool().default(false),
});
export type WorkerEnv = z.infer<typeof workerEnvSchema>;

/** `apps/realtime` (ADR-010, ADR-021 §8): no database, no bucket; verifies tokens itself. */
export const realtimeEnvSchema = z.object({
  REDIS_URL: z.string().min(1),
  PORT: z.coerce.number().int().positive().default(3001),
  LOG_LEVEL: logLevelSchema.default("info"),
  REALTIME_TOKEN_SECRET: z.string().min(1),
});
export type RealtimeEnv = z.infer<typeof realtimeEnvSchema>;

/**
 * Parses `env` against `schema`, throwing a single readable error listing
 * every invalid or missing variable (ADR-009: "the app refuses to start if
 * a variable is missing").
 */
export function parseEnv<T extends z.ZodType>(
  schema: T,
  env: Record<string, string | undefined>,
): z.infer<T> {
  const result = schema.safeParse(env);
  if (!result.success) {
    const issues = result.error.issues
      .map((issue) => `  - ${issue.path.join(".") || "(root)"}: ${issue.message}`)
      .join("\n");
    throw new Error(`Invalid environment configuration:\n${issues}`);
  }
  return result.data;
}
