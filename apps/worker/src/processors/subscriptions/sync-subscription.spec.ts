import { randomUUID } from "node:crypto";
import { getQueueToken } from "@nestjs/bullmq";
import type { Job, Queue } from "bullmq";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import {
  SUBSCRIPTIONS_QUEUE_NAME,
  SYNC_SUBSCRIPTION_JOB_NAME,
  syncSubscriptionJobId,
  type SyncSubscriptionJob,
} from "@repo/contracts";
import { bootstrapTestWorkerApp, waitFor, type TestWorkerApp } from "../../testing/test-worker-app.js";

const PROJECT = "proj_test";
const ENTITLEMENT = "entl_premium";
const DAY = 24 * 3600 * 1000;

/** What RevenueCat knows of a customer; absent = no customer (404). */
interface FakeCustomer {
  activeEntitlementExpiresAt?: number | null;
  subscriptions: Record<string, unknown>[];
}

/** RevenueCat's API v2 reads, simulated (ADR-038 §12): never the real API. */
class FakeRevenueCat {
  readonly customers = new Map<string, FakeCustomer>();
  readonly paths: string[] = [];
  failWith: number | null = null;

  readonly fetch = async (input: string | URL | Request, init?: RequestInit): Promise<Response> => {
    const url = new URL(String(input));
    this.paths.push(`${init?.method ?? "GET"} ${url.pathname}`);
    if (this.failWith) {
      return Response.json({ message: "boom" }, { status: this.failWith });
    }
    const match = url.pathname.match(new RegExp(`^/v2/projects/${PROJECT}/customers/([^/]+)(/subscriptions)?$`));
    const customer = match && this.customers.get(decodeURIComponent(match[1]!));
    if (!customer || init?.method !== "GET") {
      return Response.json({ type: "resource_missing" }, { status: 404 });
    }
    if (match[2]) {
      return Response.json({ object: "list", items: customer.subscriptions, next_page: null });
    }
    const active =
      customer.activeEntitlementExpiresAt === undefined
        ? []
        : [{ object: "customer.active_entitlement", entitlement_id: ENTITLEMENT, expires_at: customer.activeEntitlementExpiresAt }];
    return Response.json({ object: "customer", id: match[1], active_entitlements: { object: "list", items: active } });
  };
}

function subscription(overrides: Record<string, unknown>) {
  return {
    object: "subscription",
    id: `sub_${randomUUID()}`,
    product_id: "prod_monthly",
    starts_at: Date.parse("2026-10-01T08:00:00Z"),
    current_period_starts_at: Date.parse("2026-10-01T08:00:00Z"),
    current_period_ends_at: Date.now() + 20 * DAY,
    ends_at: Date.now() + 20 * DAY,
    gives_access: true,
    pending_payment: false,
    auto_renewal_status: "will_renew",
    status: "active",
    store: "app_store",
    environment: "production",
    entitlements: { object: "list", items: [{ object: "entitlement", id: ENTITLEMENT }] },
    ...overrides,
  };
}

/**
 * `sync-subscription` (ADR-014, ADR-038 §12) on real Postgres and Redis: the `premium` row
 * mirrors the entitlement RevenueCat computes; RevenueCat's API v2 is simulated.
 */
describe("sync-subscription (integration)", () => {
  let ctx: TestWorkerApp;
  let revenueCat: FakeRevenueCat;
  const users: string[] = [];

  const sql = async (text: string, params: unknown[]) => (await ctx.db.$client.query(text, params)).rows;
  const athlete = async () => {
    const id = randomUUID();
    users.push(id);
    await sql('insert into "user" (id, name, email) values ($1, $2, $3)', [id, "Athlète Premium", `${id}@test.local`]);
    return id;
  };
  const premiumRow = async (userId: string) =>
    (await sql("select * from subscriptions.user_subscription where user_id = $1", [userId]))[0];

  async function sync(userId: string, opts: { attempts?: number } = {}): Promise<Job> {
    const queue = ctx.app.get<Queue<SyncSubscriptionJob>>(getQueueToken(SUBSCRIPTIONS_QUEUE_NAME));
    const job = await queue.add(SYNC_SUBSCRIPTION_JOB_NAME, { userId }, {
      jobId: `${syncSubscriptionJobId(userId)}-${randomUUID()}`,
      attempts: opts.attempts ?? 1,
    });
    await waitFor(async () => ((await job.isCompleted()) || (await job.isFailed()) ? true : undefined));
    return (await queue.getJob(job.id!))!;
  }

  beforeAll(async () => {
    revenueCat = new FakeRevenueCat();
    ctx = await bootstrapTestWorkerApp({
      revenueCat: { apiKey: "sk_test", projectId: PROJECT, premiumEntitlementId: ENTITLEMENT, fetch: revenueCat.fetch },
    });
  }, 60_000);

  afterAll(async () => {
    if (users.length > 0) {
      await sql('delete from "user" where id = any($1)', [users]);
    }
    await ctx?.close();
  });

  it("mirrors a renewing App Store subscription and marks the athlete's events processed", async () => {
    const userId = await athlete();
    const endsAt = Date.now() + 20 * DAY;
    revenueCat.customers.set(userId, {
      activeEntitlementExpiresAt: endsAt,
      subscriptions: [subscription({ current_period_ends_at: endsAt, ends_at: endsAt })],
    });
    await sql(
      "insert into subscriptions.revenuecat_event (id, user_id, type, payload) values ($1, $2, 'INITIAL_PURCHASE', '{}')",
      [`evt-${randomUUID()}`, userId],
    );

    expect(await (await sync(userId)).getState()).toBe("completed");
    expect(await premiumRow(userId)).toMatchObject({
      entitlement_id: "premium",
      is_active: true,
      product_id: "prod_monthly",
      store: "app_store",
      period_type: "normal",
      will_renew: true,
      purchased_at: new Date("2026-10-01T08:00:00Z"),
      expires_at: new Date(endsAt),
      grace_period_expires_at: null,
      billing_issue_detected_at: null,
      unsubscribe_detected_at: null,
      environment: "production",
    });
    expect((await premiumRow(userId))!.synced_at).toBeInstanceOf(Date);
    expect(await sql("select processed_at from subscriptions.revenuecat_event where user_id = $1", [userId])).toEqual([
      { processed_at: expect.any(Date) },
    ]);
    // v2 only: the customer, then its subscriptions.
    expect(revenueCat.paths.filter((path) => path.includes(userId))).toEqual([
      `GET /v2/projects/${PROJECT}/customers/${userId}`,
      `GET /v2/projects/${PROJECT}/customers/${userId}/subscriptions`,
    ]);
  });

  it("Promotional Premium granted then revoked: the row follows RevenueCat's entitlement", async () => {
    const userId = await athlete();
    const grantEnd = Date.now() + 90 * DAY;
    const grant = subscription({
      product_id: null,
      store: "promotional",
      starts_at: Date.now(),
      current_period_ends_at: grantEnd,
      ends_at: grantEnd,
      auto_renewal_status: "will_not_renew",
    });
    revenueCat.customers.set(userId, { activeEntitlementExpiresAt: grantEnd, subscriptions: [grant] });
    await sync(userId);
    expect(await premiumRow(userId)).toMatchObject({
      is_active: true,
      store: "promotional",
      period_type: "promotional",
      product_id: null,
      will_renew: false,
      unsubscribe_detected_at: null,
      expires_at: new Date(grantEnd),
    });

    const revokedAt = Date.now();
    revenueCat.customers.set(userId, {
      subscriptions: [{ ...grant, gives_access: false, status: "expired", current_period_ends_at: revokedAt, ends_at: revokedAt }],
    });
    await sync(userId);
    expect(await premiumRow(userId)).toMatchObject({ is_active: false, store: "promotional", expires_at: new Date(revokedAt) });
  });

  it("writes nothing for an athlete RevenueCat does not know", async () => {
    const userId = await athlete();
    expect(await (await sync(userId)).getState()).toBe("completed");
    expect(await premiumRow(userId)).toBeUndefined();
  });

  it("fails the job when RevenueCat fails, so it is retried; the row is untouched", async () => {
    const userId = await athlete();
    revenueCat.failWith = 503;
    try {
      const job = await sync(userId);
      expect(await job.getState()).toBe("failed");
      expect(job.failedReason).toContain("RevenueCat");
    } finally {
      revenueCat.failWith = null;
    }
    expect(await premiumRow(userId)).toBeUndefined();
  });
});

describe("sync-subscription without RevenueCat (integration)", () => {
  let ctx: TestWorkerApp;

  beforeAll(async () => {
    ctx = await bootstrapTestWorkerApp();
  }, 60_000);

  afterAll(async () => {
    await ctx?.close();
  });

  it("fails for good: « RevenueCat non configuré », no retry", async () => {
    const userId = randomUUID();
    const queue = ctx.app.get<Queue<SyncSubscriptionJob>>(getQueueToken(SUBSCRIPTIONS_QUEUE_NAME));
    const job = await queue.add(SYNC_SUBSCRIPTION_JOB_NAME, { userId }, { jobId: syncSubscriptionJobId(userId), attempts: 5 });
    await waitFor(async () => ((await job.isFailed()) ? true : undefined));
    const failed = (await queue.getJob(job.id!))!;
    expect(failed.failedReason).toBe("RevenueCat non configuré");
    expect(failed.attemptsMade).toBe(1);
  });
});
