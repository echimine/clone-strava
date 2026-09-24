import { Module } from "@nestjs/common";
import { CONFIG, loadConfig } from "./env.js";

/**
 * Provides the validated environment under the `CONFIG` token. `loadConfig()`
 * runs once, when this module's decorator metadata is evaluated (module load
 * time), so a missing env var crashes the process before anything else runs.
 */
@Module({
  providers: [{ provide: CONFIG, useValue: loadConfig() }],
  exports: [CONFIG],
})
export class ConfigModule {}
