import { Module } from "@nestjs/common";
import { LoggerModule } from "nestjs-pino";
import { ConfigModule } from "../config/config.module.js";
import { CONFIG, type RealtimeEnv } from "../config/env.js";

/**
 * Structured JSON logs via Pino (ADR-009 "Logs, in practice"). Tokens,
 * passwords and `Authorization` headers are redacted automatically. `/health`
 * is excluded from request auto-logging to keep it quiet.
 */
@Module({
  imports: [
    ConfigModule,
    LoggerModule.forRootAsync({
      imports: [ConfigModule],
      inject: [CONFIG],
      useFactory: (config: RealtimeEnv) => ({
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
          autoLogging: {
            ignore: (req: { url?: string }) => req.url === "/health",
          },
        },
      }),
    }),
  ],
  exports: [LoggerModule],
})
export class AppLoggingModule {}
