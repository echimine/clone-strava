import { randomUUID } from "node:crypto";
import { getQueueToken } from "@nestjs/bullmq";
import type { Queue } from "bullmq";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  ACCOUNTS_QUEUE_NAME,
  DELETE_ACCOUNT_JOB_NAME,
  deleteAccountJobId,
  type DeleteAccountJob,
} from "@repo/contracts";
import { DEFAULT_JOB_RETRY } from "@repo/core/infrastructure";
import { bootstrapTestWorkerApp, waitFor, type TestWorkerApp } from "../../testing/test-worker-app.js";

type Call = { url: string; method: string; authorization: string | null; body: unknown };

/**
 * RevenueCat and PostHog are third parties (ADR-024 §2): a fake `fetch` records each call and
 * answers what the spec queued, `404`/`202` by default. Never a real call.
 */
class FakeThirdParties {
  readonly calls: Call[] = [];
  readonly answers: Response[] = [];

  readonly fetch: typeof fetch = async (input, init) => {
    const headers = new Headers(init?.headers);
    this.calls.push({
      url: String(input),
      method: init?.method ?? "GET",
      authorization: headers.get("authorization"),
      body: typeof init?.body === "string" ? JSON.parse(init.body) : null,
    });
    const queued = this.answers.shift();
    if (queued) {
      return queued;
    }
    return String(input).includes("posthog")
      ? Response.json({ persons_found: 1, persons_queued_for_deletion: 1, deletion_errors: [] }, { status: 202 })
      : new Response(null, { status: 204 });
  };
}

/**
 * The `delete-account` job (ADR-038 §13): bucket prefixes, RevenueCat customer, PostHog person
 * last, then the Journal entry « Système ». Real Postgres and Redis, in-memory bucket.
 */
describe("delete-account (integration)", () => {
  let worker: TestWorkerApp;
  let queue: Queue<DeleteAccountJob>;
  const fake = new FakeThirdParties();

  const completions = (userId: string) =>
    worker.db.$client.query<{
      actor_id: string | null;
      target_id: string;
      subject_user_id: string;
      details: unknown;
      request_id: string | null;
    }>(
      `select actor_id, target_id, subject_user_id, details, request_id from audit.admin_audit_entry
       where action = 'user.delete.complete' and target_id = $1`,
      [userId],
    );
  const run = async (userId: string) => {
    await queue.add(DELETE_ACCOUNT_JOB_NAME, { userId, requestId: "req-214" }, { ...DEFAULT_JOB_RETRY, jobId: deleteAccountJobId(userId) });
    const job = await waitFor(async () => {
      const current = await queue.getJob(deleteAccountJobId(userId));
      const state = await current?.getState();
      return state === "completed" || state === "failed" || (state === "delayed" && current!.attemptsMade > 0) ? current : undefined;
    });
    return job;
  };

  beforeAll(async () => {
    worker = await bootstrapTestWorkerApp({
      revenueCat: { apiKey: "sk_test", projectId: "proj_test", premiumEntitlementId: "entl_test", fetch: fake.fetch },
      accounts: { postHog: { personalApiKey: "phx_test", projectId: "4242" }, fetch: fake.fetch },
    });
    queue = worker.app.get<Queue<DeleteAccountJob>>(getQueueToken(ACCOUNTS_QUEUE_NAME));
  }, 60_000);

  afterAll(async () => {
    await worker?.close();
  });

  beforeEach(() => {
    fake.calls.length = 0;
    fake.answers.length = 0;
  });

  it("empties the three bucket prefixes, deletes the RevenueCat customer then the PostHog person, writes « Système »", async () => {
    const userId = randomUUID();
    const otherId = randomUUID();
    for (const key of [
      `activities/${userId}/a1/track.fit`,
      `imports/${userId}/i1.gpx`,
      `avatars/${userId}/v1.jpg`,
      `activities/${otherId}/a2/track.fit`,
    ]) {
      await worker.storage.putObject(key, new Uint8Array([1]));
    }

    const job = await run(userId);
    expect(await job.getState()).toBe("completed");

    expect([...worker.storage.objects.keys()]).toEqual([`activities/${otherId}/a2/track.fit`]);
    expect(fake.calls).toEqual([
      {
        url: `https://api.revenuecat.com/v2/projects/proj_test/customers/${userId}`,
        method: "DELETE",
        authorization: "Bearer sk_test",
        body: null,
      },
      {
        url: "https://eu.posthog.com/api/projects/4242/persons/bulk_delete/",
        method: "POST",
        authorization: "Bearer phx_test",
        body: { distinct_ids: [userId], delete_events: true },
      },
    ]);
    expect((await completions(userId)).rows).toEqual([
      {
        actor_id: null,
        target_id: userId,
        subject_user_id: userId,
        details: { bucket: "deleted", revenueCat: "deleted", postHog: "deleted" },
        request_id: "req-214",
      },
    ]);
  });

  it("« already gone » is a success: RevenueCat 404, PostHog person never seen", async () => {
    const userId = randomUUID();
    fake.answers.push(
      new Response(null, { status: 404 }),
      Response.json({ persons_found: 0, persons_queued_for_deletion: 0, deletion_errors: [] }, { status: 202 }),
    );
    const job = await run(userId);
    expect(await job.getState()).toBe("completed");
    expect((await completions(userId)).rows[0]?.details).toEqual({
      bucket: "deleted",
      revenueCat: "not_found",
      postHog: "not_found",
    });
  });

  it("a RevenueCat failure retries the job before PostHog is touched, and records nothing yet", async () => {
    const userId = randomUUID();
    fake.answers.push(new Response("boom", { status: 500 }));
    const job = await run(userId);
    expect(job.attemptsMade).toBeGreaterThanOrEqual(1);
    expect(job.failedReason).toBeTruthy();
    expect(fake.calls.map((call) => call.method)).toEqual(["DELETE"]);
    expect((await completions(userId)).rows).toEqual([]);
    await job.remove();
  });

  it("PostHog's deletion_errors fail the step", async () => {
    const userId = randomUUID();
    fake.answers.push(
      new Response(null, { status: 204 }),
      Response.json({ persons_found: 1, deletion_errors: [{ person_uuid: "p", step: "events" }] }, { status: 202 }),
    );
    const job = await run(userId);
    expect(job.failedReason).toContain("PostHog");
    expect((await completions(userId)).rows).toEqual([]);
    await job.remove();
  });
});

describe("delete-account without third-party keys (integration)", () => {
  let worker: TestWorkerApp;

  beforeAll(async () => {
    worker = await bootstrapTestWorkerApp();
  }, 60_000);

  afterAll(async () => {
    await worker?.close();
  });

  it("skips RevenueCat and PostHog, still empties the bucket and writes the entry", async () => {
    const userId = randomUUID();
    await worker.storage.putObject(`avatars/${userId}/v1.jpg`, new Uint8Array([1]));
    const queue = worker.app.get<Queue<DeleteAccountJob>>(getQueueToken(ACCOUNTS_QUEUE_NAME));
    await queue.add(DELETE_ACCOUNT_JOB_NAME, { userId }, { jobId: deleteAccountJobId(userId) });
    const rows = await waitFor(async () => {
      const result = await worker.db.$client.query<{ details: unknown }>(
        "select details from audit.admin_audit_entry where action = 'user.delete.complete' and target_id = $1",
        [userId],
      );
      return result.rows.length > 0 ? result.rows : undefined;
    });
    expect(rows[0]?.details).toEqual({ bucket: "deleted", revenueCat: "skipped", postHog: "skipped" });
    expect(worker.storage.objects.has(`avatars/${userId}/v1.jpg`)).toBe(false);
  });
});
