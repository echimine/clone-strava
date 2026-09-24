import { Module } from "@nestjs/common";
import { LoggerModule } from "nestjs-pino";
import { randomUUID } from "node:crypto";
import type { IncomingMessage } from "node:http";
import { ConfigModule } from "../config/config.module.js";
import { CONFIG, type ApiEnv } from "../config/env.js";

/**
 * Structured JSON logs via Pino (ADR-009 "Logs, in practice"). Each HTTP
 * request gets a correlation `requestId`, copied into job payloads and
 * published events so an activity can be followed from the API to the
 * worker and then the WS server. Tokens, passwords and `Authorization`
 * headers are redacted automatically.
 */
@Module({
  imports: [
    ConfigModule,
    LoggerModule.forRootAsync({
      imports: [ConfigModule],
      inject: [CONFIG],
      useFactory: (config: ApiEnv) => ({
        pinoHttp: {
          level: config.LOG_LEVEL,
          genReqId: (req: IncomingMessage) =>
            (req.headers["x-request-id"] as string | undefined) ?? randomUUID(),
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
