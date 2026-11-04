import { randomUUID } from "node:crypto";
import { getQueueToken } from "@nestjs/bullmq";
import type { Queue } from "bullmq";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { SUBSCRIPTIONS_QUEUE_NAME, syncSubscriptionJobId } from "@repo/contracts";
import type { AdminTestApp } from "../testing/admin-test-app.js";

const SECRET = "Bearer test-webhook-secret";

/**
 * `POST /v1/webhooks/revenuecat` (ADR-014, ADR-038 §12): each event stored once for the user
 * sheet's history, then `sync-subscription` queued; the worker re-reads RevenueCat.
 */
describe("POST /v1/webhooks/revenuecat (integration)", () => {
  let t: AdminTestApp;
  let queue: Queue;

  const deliver = (event: Record<string, unknown>, authorization = SECRET) =>
    fetch(`${t.baseUrl}/v1/webhooks/revenuecat`, {
      method: "POST",
      headers: { "content-type": "application/json", authorization },
      body: JSON.stringify({ api_version: "1.0", event }),
    });
  const storedEvents = (userId: string) =>
    t.sql<{ id: string; type: string; payload: { event: { product_id?: string } } }>(
      "select id, type, payload from subscriptions.revenuecat_event where user_id = $1",
      [userId],
    );

  beforeAll(async () => {
    const { bootstrapAdminTestApp } = await import("../testing/admin-test-app.js");
    const { SubscriptionsModule } = await import("@repo/core/subscriptions");
    const { CONFIG } = await import("../config/env.js");
    const { RevenueCatWebhookController } = await import("./revenuecat.controller.js");
    t = await bootstrapAdminTestApp({
      imports: [SubscriptionsModule],
      controllers: [RevenueCatWebhookController],
      providers: [{ provide: CONFIG, useValue: { REVENUECAT_WEBHOOK_SECRET: SECRET } }],
    });
    queue = t.app.get<Queue>(getQueueToken(SUBSCRIPTIONS_QUEUE_NAME));
  }, 60_000);

  afterAll(async () => {
    await t?.close();
  });

  it("stores a Promotional Premium event and queues the sync; a redelivery is stored and queued once", async () => {
    const athlete = await t.seedUser("Webhook");
    const event = {
      id: `evt-${randomUUID()}`,
      type: "NON_RENEWING_PURCHASE",
      app_user_id: athlete,
      store: "PROMOTIONAL",
      period_type: "PROMOTIONAL",
      product_id: "rc_promo_premium_three_month",
    };
    expect(await (await deliver(event)).json()).toEqual({ received: true });
    expect(await storedEvents(athlete)).toEqual([
      { id: event.id, type: "NON_RENEWING_PURCHASE", payload: { api_version: "1.0", event } },
    ]);
    const job = await queue.getJob(syncSubscriptionJobId(athlete));
    expect(job?.data).toMatchObject({ userId: athlete });

    // The job ran meanwhile; the same event delivered again queues nothing.
    await job!.remove();
    expect((await deliver(event)).status).toBe(200);
    expect(await storedEvents(athlete)).toHaveLength(1);
    expect(await queue.getJob(syncSubscriptionJobId(athlete))).toBeUndefined();
  });

  it("ignores a customer that is not one of our accounts (anonymous id, deleted account)", async () => {
    const deleted = randomUUID();
    for (const appUserId of ["$RCAnonymousID:abc", deleted]) {
      const response = await deliver({ id: `evt-${randomUUID()}`, type: "EXPIRATION", app_user_id: appUserId });
      expect(response.status).toBe(200);
    }
    expect(await storedEvents(deleted)).toEqual([]);
    expect(await queue.getJob(syncSubscriptionJobId(deleted))).toBeUndefined();
  });

  it("401 with a wrong secret; nothing stored", async () => {
    const athlete = await t.seedUser("Intrus");
    const response = await deliver({ id: `evt-${randomUUID()}`, type: "EXPIRATION", app_user_id: athlete }, "Bearer nope");
    expect(response.status).toBe(401);
    expect(await storedEvents(athlete)).toEqual([]);
  });
});
