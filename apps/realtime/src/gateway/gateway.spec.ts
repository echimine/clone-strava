import { randomUUID } from "node:crypto";
import type { INestApplication } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import jwt from "jsonwebtoken";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import { WebSocket } from "ws";
import {
  REALTIME_GRANT_AUDIENCE,
  REALTIME_TOKEN_ALGORITHM,
  REALTIME_TOKEN_AUDIENCE,
  REALTIME_TOKEN_ISSUER,
  activityTopic,
  userTopic,
} from "@repo/realtime";

// `ConfigModule` parses the environment when it is imported: set it first,
// and import the gateway module only in `beforeAll`.
const SECRET = vi.hoisted(() => {
  const secret = "gateway-spec-secret-at-least-32-characters";
  process.env.REDIS_URL = "redis://127.0.0.1:6379";
  process.env.REALTIME_TOKEN_SECRET = secret;
  return secret;
});

type ServerMessage = { a: string; topic?: string; reason?: string };

/**
 * The gateway over a real WebSocket and Redis (ADR-010 §10): subscribing
 * to `activity:{id}` with a subscription grant (ADR-034 §5).
 */
describe("gateway subscriptions (integration)", () => {
  let app: INestApplication;
  let url: string;
  const userId = randomUUID();
  const topic = activityTopic(randomUUID());

  function sign(claims: object, audience: string): string {
    return jwt.sign(claims, SECRET, {
      algorithm: REALTIME_TOKEN_ALGORITHM,
      issuer: REALTIME_TOKEN_ISSUER,
      audience,
      expiresIn: 60,
    });
  }

  const connectionToken = () => sign({ sub: userId, topics: [userTopic(userId)] }, REALTIME_TOKEN_AUDIENCE);
  const grantFor = (subject: string, grantedTopic: string) =>
    sign({ sub: subject, topic: grantedTopic }, REALTIME_GRANT_AUDIENCE);

  async function connect(): Promise<{ ws: WebSocket; next: () => Promise<ServerMessage> }> {
    const ws = new WebSocket(url, { headers: { authorization: `Bearer ${connectionToken()}` } });
    const queue: ServerMessage[] = [];
    const waiters: ((message: ServerMessage) => void)[] = [];
    ws.on("message", (raw: Buffer) => {
      const message = JSON.parse(raw.toString()) as ServerMessage;
      const waiter = waiters.shift();
      if (waiter) waiter(message);
      else queue.push(message);
    });
    await new Promise<void>((resolve, reject) => {
      ws.once("open", () => resolve());
      ws.once("error", reject);
    });
    const next = () =>
      new Promise<ServerMessage>((resolve) => {
        const queued = queue.shift();
        if (queued) resolve(queued);
        else waiters.push(resolve);
      });
    return { ws, next };
  }

  async function subscribe(message: Record<string, unknown>): Promise<ServerMessage> {
    const { ws, next } = await connect();
    try {
      ws.send(JSON.stringify({ a: "sub", ...message }));
      return await next();
    } finally {
      ws.close();
    }
  }

  beforeAll(async () => {
    const { GatewayModule } = await import("./gateway.module.js");
    const moduleRef = await Test.createTestingModule({ imports: [GatewayModule] }).compile();
    app = moduleRef.createNestApplication({ logger: false });
    await app.listen(0);
    const address = app.getHttpServer().address();
    url = `ws://127.0.0.1:${typeof address === "object" && address ? address.port : 0}/ws`;
  });

  afterAll(async () => {
    await app?.close();
  });

  it("refuses activity:{id} without a grant", async () => {
    expect(await subscribe({ topic })).toEqual({ a: "sub:err", topic, reason: "forbidden" });
  });

  it("accepts activity:{id} with a grant for that topic and user", async () => {
    expect(await subscribe({ topic, grant: grantFor(userId, topic) })).toEqual({ a: "sub:ok", topic });
  });

  it("refuses a connection token presented as a grant", async () => {
    const tokenListingTheTopic = sign({ sub: userId, topics: [topic] }, REALTIME_TOKEN_AUDIENCE);
    expect(await subscribe({ topic, grant: tokenListingTheTopic })).toEqual({ a: "sub:err", topic, reason: "forbidden" });
  });

  it("refuses a grant issued to another user or for another topic", async () => {
    expect(await subscribe({ topic, grant: grantFor(randomUUID(), topic) })).toMatchObject({ a: "sub:err" });
    expect(await subscribe({ topic, grant: grantFor(userId, activityTopic(randomUUID())) })).toMatchObject({
      a: "sub:err",
    });
  });

  it("still accepts the topics of the connection token without a grant", async () => {
    expect(await subscribe({ topic: userTopic(userId) })).toEqual({ a: "sub:ok", topic: userTopic(userId) });
  });

  it("refuses a grant as a connection token (401 before the upgrade)", async () => {
    const ws = new WebSocket(url, { headers: { authorization: `Bearer ${grantFor(userId, topic)}` } });
    const status = await new Promise<number | undefined>((resolve) => {
      ws.once("unexpected-response", (_req, res) => resolve(res.statusCode));
      ws.once("open", () => resolve(101));
      ws.once("error", () => resolve(undefined));
    });
    ws.terminate();
    expect(status).toBe(401);
  });
});
