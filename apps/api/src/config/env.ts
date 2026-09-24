import { parseEnv, apiEnvSchema, type ApiEnv } from "@repo/contracts";

/** Injection token for the parsed, validated environment (ADR-009 "Common foundation"). */
export const CONFIG = Symbol("API_CONFIG");

/**
 * Parses `process.env` against `apiEnvSchema`. Called at module-definition
 * time (see `ConfigModule`), so an invalid or missing variable throws before
 * Nest even starts bootstrapping (ADR-009: "the app refuses to start if a
 * variable is missing").
 */
export function loadConfig(): ApiEnv {
  return parseEnv(apiEnvSchema, process.env);
}

export type { ApiEnv };
