import { Module } from "@nestjs/common";
import { LoggerModule } from "nestjs-pino";
import { ConfigModule } from "../config/config.module.js";
import { CONFIG, type WorkerEnv } from "../config/env.js";

/**
 * Structured JSON logs via Pino (ADR-009 "Logs, in practice"). The worker has
 * no HTTP server, so `pinoHttp` here only configures the underlying logger
 * instance (level, redaction); no request middleware is installed.
 */
@Module({
  imports: [
    ConfigModule,
    LoggerModule.forRootAsync({
      imports: [ConfigModule],
      inject: [CONFIG],
      useFactory: (config: WorkerEnv) => ({
        pinoHttp: {
          level: config.LOG_LEVEL,
          redact: {
            paths: [
              "req.headers.authorization",
              "req.headers.cookie",
              "*.password",
              "*.token",
            ],
            censor: "[Redacted]",
          },
        },
      }),
    }),
  ],
  exports: [LoggerModule],
})
export class AppLoggingModule {}
