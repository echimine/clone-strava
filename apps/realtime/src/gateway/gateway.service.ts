import type { IncomingMessage, Server as HttpServer } from "node:http";
import type { Duplex } from "node:stream";
import {
  Inject,
  Injectable,
  Logger,
  type BeforeApplicationShutdown,
  type OnModuleInit,
} from "@nestjs/common";
import { HttpAdapterHost } from "@nestjs/core";
import Redis from "ioredis";
import { WebSocket, WebSocketServer } from "ws";
import {
  CLOSE_SERVER_SHUTDOWN,
  TopicRegistry,
  createRedisEventSource,
  parseClientMessage,
  type RealtimeEventSource,
} from "@repo/realtime";
import { CONFIG, type RealtimeEnv } from "../config/env.js";
import { REDIS_CLIENT } from "../redis/redis.module.js";
import { createConnectionState, type ConnectionState } from "./connection-state.js";
import { extractBearerToken, verifyRealtimeToken, verifySubscriptionGrant } from "./token-verifier.js";
import {
  handleClientMessage,
  recordMessageAndCheckQuota,
  type GrantVerifier,
} from "./message-handling.js";
import {
  CLOSE_HEARTBEAT_TIMEOUT,
  HEARTBEAT_CHECK_INTERVAL_MS,
  HEARTBEAT_TIMEOUT_MS,
  MAX_PAYLOAD_BYTES,
} from "./quotas.js";

const WS_PATH = "/ws";

/**
 * The `realtime` gateway (ADR-010): authenticates, holds connections and
 * routes events by topic. No business logic, no database access.
 *
 * We do not use `@nestjs/platform-ws`: hooking the HTTP server's `upgrade`
 * event ourselves lets us reject an invalid token with `401` before the
 * WebSocket handshake completes (ADR-010 §2).
 */
@Injectable()
export class GatewayService implements OnModuleInit, BeforeApplicationShutdown {
  private readonly logger = new Logger(GatewayService.name);
  private readonly wss = new WebSocketServer({ noServer: true, maxPayload: MAX_PAYLOAD_BYTES });
  private readonly registry = new TopicRegistry<WebSocket>();
  private readonly connections = new Map<WebSocket, ConnectionState>();
  private readonly subscriberRedis: Redis;
  private eventSource: RealtimeEventSource | undefined;
  private heartbeatInterval: NodeJS.Timeout | undefined;

  constructor(
    private readonly httpAdapterHost: HttpAdapterHost,
    @Inject(CONFIG) private readonly config: RealtimeEnv,
    @Inject(REDIS_CLIENT) private readonly redis: Redis,
  ) {
    this.subscriberRedis = this.redis.duplicate();
  }

  async onModuleInit(): Promise<void> {
    const httpServer = this.httpAdapterHost.httpAdapter.getHttpServer() as HttpServer;
    httpServer.on("upgrade", (req, socket, head) => {
      this.handleUpgrade(req, socket, head).catch((error: unknown) => {
        this.logger.error("Unhandled error while upgrading a connection", error);
        socket.destroy();
      });
    });

    this.eventSource = createRedisEventSource(this.subscriberRedis);
    this.eventSource.onMessage((message) => {
      for (const topic of message.topics) {
        for (const conn of this.registry.connectionsFor(topic)) {
          if (conn.readyState === WebSocket.OPEN) {
            conn.send(JSON.stringify(message.envelope));
          }
        }
      }
    });
    await this.eventSource.subscribe();

    this.heartbeatInterval = setInterval(() => this.checkHeartbeats(), HEARTBEAT_CHECK_INTERVAL_MS);
  }

  async beforeApplicationShutdown(): Promise<void> {
    if (this.heartbeatInterval) {
      clearInterval(this.heartbeatInterval);
    }
    for (const ws of this.connections.keys()) {
      ws.close(CLOSE_SERVER_SHUTDOWN, "shutdown");
    }
    this.connections.clear();
    if (this.eventSource) {
      await this.eventSource.close();
    }
  }

  /** Number of currently open connections, reported on `/health` (ADR-010 §5). */
  getConnectionCount(): number {
    return this.connections.size;
  }

  private async handleUpgrade(req: IncomingMessage, socket: Duplex, head: Buffer): Promise<void> {
    const url = new URL(req.url ?? "", "http://localhost");
    if (url.pathname !== WS_PATH) {
      socket.destroy();
      return;
    }

    // Any connection presenting an `Origin` header (browser) is refused
    // (ADR-010 §3): the backoffice never opens realtime connections.
    if (req.headers.origin) {
      this.rejectUpgrade(socket, 403, "origin_not_allowed");
      return;
    }

    const token = extractBearerToken(req.headers.authorization);
    const claims = token ? verifyRealtimeToken(token, this.config.REALTIME_TOKEN_SECRET) : null;
    if (!claims) {
      this.rejectUpgrade(socket, 401, "invalid_token");
      return;
    }

    this.wss.handleUpgrade(req, socket, head, (ws) => {
      this.registerConnection(ws, claims);
    });
  }

  private rejectUpgrade(socket: Duplex, statusCode: number, reason: string): void {
    const statusText = statusCode === 401 ? "Unauthorized" : "Forbidden";
    socket.write(
      `HTTP/1.1 ${statusCode} ${statusText}\r\nConnection: close\r\nContent-Length: 0\r\n\r\n`,
    );
    socket.destroy();
    this.logger.debug(`Upgrade rejected: ${reason}`);
  }

  private registerConnection(
    ws: WebSocket,
    claims: ConnectionState["claims"],
  ): void {
    const state = createConnectionState(claims, Date.now());
    this.connections.set(ws, state);

    ws.on("message", (raw: Buffer) => {
      this.handleMessage(ws, state, raw.toString());
    });

    ws.on("close", () => {
      this.registry.removeConnection(ws);
      this.connections.delete(ws);
    });

    ws.on("error", (error) => {
      this.logger.warn(`Connection error: ${error.message}`);
    });
  }

  private handleMessage(ws: WebSocket, state: ConnectionState, raw: string): void {
    const withinQuota = recordMessageAndCheckQuota(state, Date.now());
    if (!withinQuota) {
      ws.close(4008, "quota_exceeded");
      return;
    }

    const parsed = parseClientMessage(raw);
    if (!parsed.success) {
      // Unreadable or unknown message: ignored, never an exception (ADR-010 §5).
      return;
    }

    const handled = handleClientMessage(state, parsed.message, this.verifyGrant);
    switch (handled.kind) {
      case "sub":
        if (handled.result === "ok") {
          this.registry.subscribe(ws, handled.topic);
          this.send(ws, { a: "sub:ok", topic: handled.topic });
        } else {
          this.send(ws, { a: "sub:err", topic: handled.topic, reason: handled.result });
        }
        break;
      case "unsub":
        this.registry.unsubscribe(ws, handled.topic);
        break;
      case "ping":
        this.send(ws, { a: "pong" });
        break;
    }
  }

  /** Subscription grants are verified locally, like the connection token (ADR-034 §5). */
  private readonly verifyGrant: GrantVerifier = (grant, topic, userId) =>
    verifySubscriptionGrant(grant, this.config.REALTIME_TOKEN_SECRET, { topic, userId });

  private send(ws: WebSocket, message: Record<string, unknown>): void {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify(message));
    }
  }

  private checkHeartbeats(): void {
    const now = Date.now();
    for (const [ws, state] of this.connections) {
      if (now - state.lastMessageAt > HEARTBEAT_TIMEOUT_MS) {
        ws.close(CLOSE_HEARTBEAT_TIMEOUT, "heartbeat_timeout");
      }
    }
  }
}
