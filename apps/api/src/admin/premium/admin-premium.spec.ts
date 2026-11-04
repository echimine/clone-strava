import { randomUUID } from "node:crypto";
import { getQueueToken } from "@nestjs/bullmq";
import { NotFoundException } from "@nestjs/common";
import type { Queue } from "bullmq";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  SUBSCRIPTIONS_QUEUE_NAME,
  syncSubscriptionJobId,
  type AdminUserListResponse,
  type AdminUserPremium,
} from "@repo/contracts";
import type { AdminTestApp } from "../../testing/admin-test-app.js";

const PROJECT = "proj_test";
const ENTITLEMENT = "entl_premium";
const DAY = 24 * 3600 * 1000;

type Entry = { action: string; target_id: string; subject_user_id: string; reason: string | null; details: unknown };
type Call = { method: string; path: string; body: Record<string, unknown> | undefined };

/**
 * RevenueCat's API v2 as far as Promotional Premium needs it, in memory: customers and their
 * granted entitlement. Never the real API (ADR-038 §12: tested with simulated responses).
 */
class FakeRevenueCat {
  readonly customers = new Map<string, { grantExpiresAt: number | null }>();
  calls: Call[] = [];
  /** Answers every call with this status (RevenueCat failing). */
  failWith: number | null = null;

  readonly fetch = async (input: string | URL | Request, init?: RequestInit): Promise<Response> => {
    const url = new URL(String(input));
    const method = init?.method ?? "GET";
    const body = init?.body ? (JSON.parse(String(init.body)) as Record<string, unknown>) : undefined;
    this.calls.push({ method, path: url.pathname, body });
    expect(url.origin).toBe("https://api.revenuecat.com");
    expect(new Headers(init?.headers).get("authorization")).toBe("Bearer sk_test");
    if (this.failWith) {
      return Response.json({ message: "boom" }, { status: this.failWith });
    }
    const projectPath = `/v2/projects/${PROJECT}/customers`;
    if (method === "POST" && url.pathname === projectPath) {
      const id = String(body?.id);
      if (this.customers.has(id)) {
        return Response.json({ type: "resource_already_exists" }, { status: 409 });
      }
      this.customers.set(id, { grantExpiresAt: null });
      return Response.json({ object: "customer", id }, { status: 201 });
    }
    const action = url.pathname.match(new RegExp(`^${projectPath}/([^/]+)/actions/(\\w+)$`));
    if (method === "POST" && action) {
      const customer = this.customers.get(decodeURIComponent(action[1]!));
      if (!customer) {
        return Response.json({ type: "resource_missing" }, { status: 404 });
      }
      expect(body?.entitlement_id).toBe(ENTITLEMENT);
      customer.grantExpiresAt = action[2] === "grant_entitlement" ? Number(body?.expires_at) : null;
      return Response.json({ object: "customer", id: action[1] }, { status: action[2] === "grant_entitlement" ? 201 : 200 });
    }
    return Response.json({ type: "not_found" }, { status: 404 });
  };
}

/**
 * The user sheet's « Premium » section and its actions (ADR-038 §12, §17), the users list's
 * Premium filter and « Fin » column, on real Postgres and Redis; RevenueCat is simulated.
 */
describe("/v1/admin/users/:id/premium (integration)", () => {
  let t: AdminTestApp;
  let unconfigured: AdminTestApp;
  let revenueCat: FakeRevenueCat;
  let queue: Queue;
  const admin = randomUUID();

  const json = async <T,>(response: Response, status = 200): Promise<T> => {
    expect(response.status, await response.clone().text()).toBe(status);
    return (await response.json()) as T;
  };
  const errorCode = async (response: Response) => ((await response.json()) as { error: { code: string } }).error.code;
  const entries = (subject: string) =>
    t.sql<Entry>("select * from audit.admin_audit_entry where subject_user_id = $1 order by created_at", [subject]);
  const queuedSync = (userId: string) => queue.getJob(syncSubscriptionJobId(userId));
  const premiumRow = (userId: string, values: string, params: unknown[] = []) =>
    t.sql(
      `insert into subscriptions.user_subscription
         (user_id, is_active, product_id, store, period_type, will_renew, purchased_at, expires_at,
          grace_period_expires_at, billing_issue_detected_at, unsubscribe_detected_at, environment, synced_at)
       values ($1, ${values})`,
      [userId, ...params],
    );

  beforeAll(async () => {
    const { bootstrapAdminTestApp } = await import("../../testing/admin-test-app.js");
    const { ActivitiesModule } = await import("@repo/core/activities");
    const { ModerationModule } = await import("@repo/core/moderation");
    const { EmailJobsModule } = await import("@repo/core/notifications");
    const { SocialModule } = await import("@repo/core/social");
    const { RevenueCatModule, SubscriptionsModule } = await import("@repo/core/subscriptions");
    const { UsersModule } = await import("@repo/core/users");
    const { AthleteIdentities } = await import("../../identities/athlete-identities.js");
    const { SanctionNotices } = await import("../sanctions/sanction-notices.js");
    const { AdminUsersController } = await import("../users/admin-users.controller.js");
    const { AdminUserAssembler } = await import("../users/admin-user-assembler.js");
    const { AdminPremiumController } = await import("./admin-premium.controller.js");
    const { AdminPremiumAssembler } = await import("./admin-premium-assembler.js");

    revenueCat = new FakeRevenueCat();
    const boot = (configured: boolean) => {
      let app: AdminTestApp | undefined;
      const getAccountForAdmin = async (id: string) => {
        const [row] = await app!.sql('select id from "user" where id = $1', [id]);
        if (!row) {
          throw new NotFoundException({ code: "user_not_found", message: "Utilisateur introuvable" });
        }
        return row;
      };
      return bootstrapAdminTestApp({
        imports: [
          ActivitiesModule,
          EmailJobsModule,
          ModerationModule,
          SocialModule,
          SubscriptionsModule,
          UsersModule,
          ...(configured
            ? [
                RevenueCatModule.forRoot({
                  apiKey: "sk_test",
                  projectId: PROJECT,
                  premiumEntitlementId: ENTITLEMENT,
                  fetch: revenueCat.fetch,
                }),
              ]
            : []),
        ],
        controllers: [AdminPremiumController, AdminUsersController],
        providers: [AdminPremiumAssembler, AdminUserAssembler, AthleteIdentities, SanctionNotices],
        authService: { getAccountForAdmin },
      }).then((booted) => (app = booted));
    };
    t = await boot(true);
    unconfigured = await boot(false);
    queue = t.app.get<Queue>(getQueueToken(SUBSCRIPTIONS_QUEUE_NAME));
  }, 60_000);

  afterAll(async () => {
    await t?.close();
    await unconfigured?.close();
  });

  beforeEach(() => {
    revenueCat.calls = [];
    revenueCat.failWith = null;
  });

  describe("GET :id/premium (our tables only)", () => {
    it("« Jamais abonné »: no row, no history, the RevenueCat link, configured", async () => {
      const athlete = await t.seedUser("Jamais Abonné");
      expect(await json<AdminUserPremium>(await t.call(`/admin/users/${athlete}/premium`, admin))).toEqual({
        configured: true,
        state: "never",
        detail: null,
        history: [],
        revenueCatUrl: `https://app.revenuecat.com/projects/${PROJECT}/customers/${athlete}`,
      });
      expect(revenueCat.calls).toEqual([]);
    });

    it("the detail of the row and the history of RevenueCat events, newest first, without raw JSON", async () => {
      const athlete = await t.seedUser("Payant Sandbox");
      await premiumRow(
        athlete,
        `true, 'nervo_monthly', 'app_store', 'normal', false, '2026-10-01T08:00:00Z', now() + interval '20 days',
         null, null, '2026-10-20T08:00:00Z', 'sandbox', '2026-10-20T08:05:00Z'`,
      );
      const event = (id: string, type: string, details: Record<string, unknown>, receivedAt: string) =>
        t.sql(
          "insert into subscriptions.revenuecat_event (id, user_id, type, payload, received_at) values ($1, $2, $3, $4, $5)",
          [id, athlete, type, { api_version: "1.0", event: { id, type, app_user_id: athlete, ...details } }, receivedAt],
        );
      await event(
        `evt-${randomUUID()}`,
        "INITIAL_PURCHASE",
        {
          event_timestamp_ms: Date.parse("2026-10-01T08:00:00Z"),
          product_id: "nervo_monthly",
          store: "APP_STORE",
          period_type: "NORMAL",
          expiration_at_ms: Date.parse("2026-11-01T08:00:00Z"),
          environment: "SANDBOX",
        },
        "2026-10-01T08:00:05Z",
      );
      const cancellation = `evt-${randomUUID()}`;
      await event(cancellation, "CANCELLATION", { store: "APP_STORE", environment: "SANDBOX" }, "2026-10-20T08:00:00Z");

      const premium = await json<AdminUserPremium>(await t.call(`/admin/users/${athlete}/premium`, admin));
      expect(premium.state).toBe("cancelled");
      expect(premium.detail).toMatchObject({
        productId: "nervo_monthly",
        store: "app_store",
        periodType: "normal",
        purchasedAt: "2026-10-01T08:00:00.000Z",
        willRenew: false,
        unsubscribeDetectedAt: "2026-10-20T08:00:00.000Z",
        billingIssueDetectedAt: null,
        gracePeriodExpiresAt: null,
        sandbox: true,
        syncedAt: "2026-10-20T08:05:00.000Z",
      });
      expect(premium.history).toEqual([
        {
          id: cancellation,
          type: "CANCELLATION",
          occurredAt: "2026-10-20T08:00:00.000Z",
          productId: null,
          store: "APP_STORE",
          periodType: null,
          expiresAt: null,
          sandbox: true,
        },
        expect.objectContaining({
          type: "INITIAL_PURCHASE",
          occurredAt: "2026-10-01T08:00:00.000Z",
          productId: "nervo_monthly",
          periodType: "NORMAL",
          expiresAt: "2026-11-01T08:00:00.000Z",
        }),
      ]);
    });

    it("404 user_not_found for an unknown account", async () => {
      const response = await t.call(`/admin/users/${randomUUID()}/premium`, admin);
      expect(response.status).toBe(404);
      expect(await errorCode(response)).toBe("user_not_found");
    });
  });

  describe("« Offrir le Premium » (premium.grant)", () => {
    it("revokes then grants the entitlement until 3 months later, queues the sync, records the Journal", async () => {
      const athlete = await t.seedUser("Offert");
      revenueCat.customers.set(athlete, { grantExpiresAt: null });
      const before = Date.now();
      const response = await t.call(`/admin/users/${athlete}/premium/promotional`, admin, {
        method: "POST",
        body: { duration: "3m", reason: "Testeur bêta" },
      });
      expect(response.status, await response.clone().text()).toBe(204);

      const customer = `/v2/projects/${PROJECT}/customers/${athlete}`;
      expect(revenueCat.calls.map((call) => `${call.method} ${call.path}`)).toEqual([
        `POST ${customer}/actions/revoke_granted_entitlement`,
        `POST ${customer}/actions/grant_entitlement`,
      ]);
      const expiresAt = revenueCat.customers.get(athlete)!.grantExpiresAt!;
      expect(expiresAt).toBeGreaterThan(before + 88 * DAY);
      expect(expiresAt).toBeLessThan(Date.now() + 93 * DAY);
      // Nothing written by hand: the sync (queued, then the webhook) is the only writer.
      expect(await t.sql("select 1 from subscriptions.user_subscription where user_id = $1", [athlete])).toEqual([]);
      expect((await queuedSync(athlete))?.data).toMatchObject({ userId: athlete });

      expect(await entries(athlete)).toEqual([
        expect.objectContaining({
          action: "premium.grant",
          target_id: athlete,
          reason: "Testeur bêta",
          details: { duration: "3m", expiresAt: new Date(expiresAt).toISOString() },
        }),
      ]);
    });

    it("creates the RevenueCat customer of an account that never opened the app", async () => {
      const athlete = await t.seedUser("Jamais Ouvert");
      const response = await t.call(`/admin/users/${athlete}/premium/promotional`, admin, {
        method: "POST",
        body: { duration: "1m", reason: "Partenaire" },
      });
      expect(response.status, await response.clone().text()).toBe(204);
      expect(revenueCat.calls.map((call) => call.path.split("/").slice(6).join("/"))).toEqual([
        "actions/revoke_granted_entitlement",
        "actions/grant_entitlement",
        "",
        "actions/grant_entitlement",
      ]);
      expect(revenueCat.calls[2]).toMatchObject({ method: "POST", body: { id: athlete } });
      expect(revenueCat.customers.get(athlete)?.grantExpiresAt).toBeGreaterThan(Date.now() + 27 * DAY);
    });

    it("400 reason_required without a reason, 422 for a length outside the closed choice; nothing called", async () => {
      const athlete = await t.seedUser("Sans Motif");
      const noReason = await t.call(`/admin/users/${athlete}/premium/promotional`, admin, {
        method: "POST",
        body: { duration: "1m" },
      });
      expect(noReason.status).toBe(400);
      expect(await errorCode(noReason)).toBe("reason_required");
      const badDuration = await t.call(`/admin/users/${athlete}/premium/promotional`, admin, {
        method: "POST",
        body: { duration: "2m", reason: "Geste" },
      });
      expect(badDuration.status).toBe(422);
      expect(revenueCat.calls).toEqual([]);
      expect(await entries(athlete)).toEqual([]);
    });

    it("502 revenuecat_unavailable when RevenueCat fails; nothing in the Journal", async () => {
      const athlete = await t.seedUser("Panne");
      revenueCat.failWith = 500;
      const response = await t.call(`/admin/users/${athlete}/premium/promotional`, admin, {
        method: "POST",
        body: { duration: "1m", reason: "Geste" },
      });
      expect(response.status).toBe(502);
      expect(await errorCode(response)).toBe("revenuecat_unavailable");
      expect(await entries(athlete)).toEqual([]);
    });
  });

  describe("« Retirer le Premium offert » (premium.revoke)", () => {
    it("revokes the granted entitlement at once and queues the sync", async () => {
      const athlete = await t.seedUser("Retiré");
      revenueCat.customers.set(athlete, { grantExpiresAt: Date.now() + 30 * DAY });
      const response = await t.call(`/admin/users/${athlete}/premium/promotional`, admin, {
        method: "DELETE",
        body: { reason: "Fin du partenariat" },
      });
      expect(response.status, await response.clone().text()).toBe(204);
      expect(revenueCat.calls).toEqual([
        {
          method: "POST",
          path: `/v2/projects/${PROJECT}/customers/${athlete}/actions/revoke_granted_entitlement`,
          body: { entitlement_id: ENTITLEMENT },
        },
      ]);
      expect(revenueCat.customers.get(athlete)?.grantExpiresAt).toBeNull();
      expect(await queuedSync(athlete)).toBeDefined();
      expect(await entries(athlete)).toEqual([
        expect.objectContaining({ action: "premium.revoke", reason: "Fin du partenariat" }),
      ]);
    });
  });

  describe("« Resynchroniser » (premium.sync)", () => {
    it("queues sync-subscription once, records the Journal without a reason", async () => {
      const athlete = await t.seedUser("Resync");
      expect(
        await json(await t.call(`/admin/users/${athlete}/premium/sync`, admin, { method: "POST", requestId: "req-1" }), 202),
      ).toEqual({ queued: true });
      expect((await queuedSync(athlete))?.data).toEqual({ userId: athlete, requestId: "req-1" });
      expect(await json(await t.call(`/admin/users/${athlete}/premium/sync`, admin, { method: "POST" }), 202)).toEqual({
        queued: false,
      });
      expect(revenueCat.calls).toEqual([]);
      expect(await entries(athlete)).toEqual([
        expect.objectContaining({ action: "premium.sync", reason: null }),
        expect.objectContaining({ action: "premium.sync", reason: null }),
      ]);
    });
  });

  describe("without RevenueCat (« RevenueCat non configuré »)", () => {
    it("reads Premium, says it is not configured; the three actions answer 503 and record nothing", async () => {
      const athlete = await unconfigured.seedUser("Non Configuré");
      expect(await json<AdminUserPremium>(await unconfigured.call(`/admin/users/${athlete}/premium`, admin))).toMatchObject({
        configured: false,
        state: "never",
        revenueCatUrl: null,
      });
      const attempts = [
        unconfigured.call(`/admin/users/${athlete}/premium/sync`, admin, { method: "POST" }),
        unconfigured.call(`/admin/users/${athlete}/premium/promotional`, admin, {
          method: "POST",
          body: { duration: "1m", reason: "Geste" },
        }),
        unconfigured.call(`/admin/users/${athlete}/premium/promotional`, admin, {
          method: "DELETE",
          body: { reason: "Geste" },
        }),
      ];
      for (const response of await Promise.all(attempts)) {
        expect(response.status).toBe(503);
        expect(await errorCode(response)).toBe("revenuecat_not_configured");
      }
      expect(await entries(athlete)).toEqual([]);
    });
  });

  describe("users list: Premium filter and « Fin » (ADR-038 §12)", () => {
    it("filters Payant, Essai, Premium offert, Problème de paiement, Résilié, Expiré; gives the state and its end", async () => {
      const tag = `prem${randomUUID().slice(0, 6)}`;
      const seed = (name: string) => t.seedUser(`${name} ${tag}`);
      const [paying, trial, promotional, grace, billing, cancelled, expired, never] = await Promise.all(
        ["Payant", "Essai", "Offert", "Grace", "Paiement", "Resilie", "Expire", "Jamais"].map(seed),
      );
      const row = (userId: string, values: string) => premiumRow(userId, values);
      await row(paying!, `true, 'm', 'app_store', 'normal', true, now(), '2030-01-01T00:00:00Z', null, null, null, 'production', now()`);
      await row(trial!, `true, 'm', 'app_store', 'trial', true, now(), '2030-01-02T00:00:00Z', null, null, null, 'production', now()`);
      await row(
        promotional!,
        `true, null, 'promotional', 'promotional', false, now(), '2030-01-03T00:00:00Z', null, null, null, 'production', now()`,
      );
      await row(
        grace!,
        `true, 'm', 'app_store', 'normal', true, now(), now() - interval '1 day', '2030-01-04T00:00:00Z', now(), null, 'production', now()`,
      );
      await row(billing!, `true, 'm', 'app_store', 'normal', true, now(), '2030-01-05T00:00:00Z', null, now(), null, 'production', now()`);
      await row(cancelled!, `true, 'm', 'app_store', 'normal', false, now(), '2030-01-06T00:00:00Z', null, null, now(), 'production', now()`);
      await row(expired!, `false, 'm', 'app_store', 'normal', false, now(), '2026-01-07T00:00:00Z', null, null, null, 'production', now()`);
      // Searching by name: the fake `getPublicIdentities` reads `user.name`, the list searches the profile.
      await t.sql(
        `insert into users.user_profile (user_id, first_name, last_name) select id, split_part(name, ' ', 1), $1 from "user" where name like $2`,
        [tag, `% ${tag}`],
      );

      const list = async (query: string) =>
        (await json<AdminUserListResponse>(await t.call(`/admin/users?q=${tag}&pageSize=25&${query}`, admin))).items;
      const ids = async (query: string) => (await list(query)).map((item) => item.athlete.id);

      expect(await ids("premium=paying")).toEqual([paying]);
      expect(await ids("premium=trial")).toEqual([trial]);
      expect(await ids("premium=promotional")).toEqual([promotional]);
      expect((await ids("premium=billing_issue")).sort()).toEqual([grace, billing].sort());
      expect(await ids("premium=cancelled")).toEqual([cancelled]);
      expect(await ids("premium=expired")).toEqual([expired]);

      const byId = new Map((await list("")).map((item) => [item.athlete.id, item]));
      expect(byId.get(paying!)).toMatchObject({ isPremium: true, premiumState: "paying", premiumEndsAt: "2030-01-01T00:00:00.000Z" });
      expect(byId.get(promotional!)).toMatchObject({ isPremium: true, premiumState: "promotional" });
      expect(byId.get(grace!)).toMatchObject({
        isPremium: true,
        premiumState: "grace_period",
        premiumEndsAt: "2030-01-04T00:00:00.000Z",
      });
      expect(byId.get(expired!)).toMatchObject({ isPremium: false, premiumState: "expired" });
      expect(byId.get(never!)).toMatchObject({ isPremium: false, premiumState: "never", premiumEndsAt: null });
    });
  });
});
