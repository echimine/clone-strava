import { randomUUID } from "node:crypto";
import { getQueueToken } from "@nestjs/bullmq";
import type { Queue } from "bullmq";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import {
  AVATARS_QUEUE_NAME,
  COPY_GOOGLE_AVATAR_JOB_NAME,
  copyGoogleAvatarJobId,
  type CopyGoogleAvatarJob,
} from "@repo/contracts";
import { AuthService } from "@repo/core/auth";
import { bootstrapTestAuthApp, ensureTestDatabaseMigrated, type TestAuthApp } from "./test-auth-app.js";
import { fakeGoogleIdTokens } from "./test-google-id-token.js";

/**
 * The Google photo copy is enqueued by the account hook (ADR-037 §2): once, at the creation of a
 * Google account, never on a later sign-in nor for a Sign-in code account; and by the one-off
 * backfill for existing Google accounts. Real Better Auth mount, Postgres and Redis; the queue has
 * no worker, so enqueued jobs stay waiting.
 */
describe("Google photo copy enqueuing (ADR-037 §2)", () => {
  let testApp: TestAuthApp;
  let google: ReturnType<typeof fakeGoogleIdTokens>;
  let queue: Queue<CopyGoogleAvatarJob>;

  beforeAll(async () => {
    await ensureTestDatabaseMigrated();
    testApp = await bootstrapTestAuthApp();
    google = fakeGoogleIdTokens();
    queue = testApp.app.get<Queue<CopyGoogleAvatarJob>>(getQueueToken(AVATARS_QUEUE_NAME));
  });

  afterAll(async () => {
    vi.restoreAllMocks();
    await testApp.app.close();
  });

  const uniqueEmail = (label: string) => `${label}-${randomUUID()}@example.com`;
  const photoOf = (sub: string) => `https://lh3.googleusercontent.com/a/${sub}=s96-c`;

  function randomIp(): string {
    const byte = () => Math.floor(Math.random() * 254) + 1;
    return `10.${byte()}.${byte()}.${byte()}`;
  }

  function post(path: string, body: unknown): Promise<Response> {
    return fetch(`${testApp.baseUrl}/api/auth${path}`, {
      method: "POST",
      headers: { "content-type": "application/json", "x-forwarded-for": randomIp() },
      body: JSON.stringify(body),
    });
  }

  async function signInWithGoogle(email: string, sub: string, picture?: string): Promise<string> {
    const token = google.idToken(email, sub, picture ? { picture } : {});
    const response = await post("/sign-in/social", { provider: "google", idToken: { token } });
    expect(response.status).toBe(200);
    return ((await response.json()) as { user: { id: string } }).user.id;
  }

  async function signInWithCode(email: string): Promise<string> {
    const spy = vi.spyOn(testApp.notificationsService, "sendAuthEmail");
    expect((await post("/email-otp/send-verification-otp", { email, type: "sign-in" })).status).toBe(200);
    const html = spy.mock.calls.find((call) => call[0].to === email)?.[0].html ?? "";
    const otp = /\b\d{6}\b/.exec(html.replace(/<[^>]*>/g, " "))?.[0];
    const response = await post("/sign-in/email-otp", { email, otp, name: "Jeanne Martin" });
    expect(response.status).toBe(200);
    return ((await response.json()) as { user: { id: string } }).user.id;
  }

  const copyJob = (userId: string) => queue.getJob(copyGoogleAvatarJobId(userId));

  it("enqueues the copy of the photo when Google creates the account", async () => {
    const sub = randomUUID();
    const userId = await signInWithGoogle(uniqueEmail("google-photo"), sub, photoOf(sub));

    const job = await vi.waitFor(async () => {
      const found = await copyJob(userId);
      expect(found).toBeDefined();
      return found!;
    });
    expect(job.name).toBe(COPY_GOOGLE_AVATAR_JOB_NAME);
    expect(job.data).toEqual({ userId, imageUrl: photoOf(sub) });
    expect(job.opts.attempts).toBeGreaterThan(1);
  });

  it("enqueues nothing when Google signs an existing account in", async () => {
    const email = uniqueEmail("google-again");
    const sub = randomUUID();
    const userId = await signInWithGoogle(email, sub, photoOf(sub));
    await vi.waitFor(async () => expect(await copyJob(userId)).toBeDefined());
    await (await copyJob(userId))!.remove();

    await signInWithGoogle(email, sub, photoOf(sub));

    await new Promise((resolve) => setTimeout(resolve, 200));
    expect(await copyJob(userId)).toBeUndefined();
  });

  it("enqueues nothing for a Sign-in code account nor a Google account without a photo", async () => {
    const coded = await signInWithCode(uniqueEmail("code-photo"));
    const faceless = await signInWithGoogle(uniqueEmail("google-faceless"), randomUUID());

    await new Promise((resolve) => setTimeout(resolve, 200));
    expect(await copyJob(coded)).toBeUndefined();
    expect(await copyJob(faceless)).toBeUndefined();
  });

  it("still creates the account when the queue is unreachable", async () => {
    const down = vi.spyOn(queue, "getJob").mockRejectedValueOnce(new Error("Redis unreachable"));
    const sub = randomUUID();

    const userId = await signInWithGoogle(uniqueEmail("google-queue-down"), sub, photoOf(sub));

    expect(userId).toBeDefined();
    await vi.waitFor(() => expect(down).toHaveBeenCalled());
    down.mockRestore();
  });

  it("backfills existing Google accounts with a photo, once even when replayed", async () => {
    const sub = randomUUID();
    const withPhoto = await signInWithGoogle(uniqueEmail("backfill-photo"), sub, photoOf(sub));
    const faceless = await signInWithGoogle(uniqueEmail("backfill-faceless"), randomUUID());
    const coded = await signInWithCode(uniqueEmail("backfill-code"));
    // An account from before the hook: no job was ever enqueued for it.
    await vi.waitFor(async () => expect(await copyJob(withPhoto)).toBeDefined());
    await (await copyJob(withPhoto))!.remove();
    const auth = testApp.app.get(AuthService);

    expect(await auth.backfillGoogleAvatarCopies()).toBeGreaterThanOrEqual(1);

    const job = await copyJob(withPhoto);
    expect(job?.data).toEqual({ userId: withPhoto, imageUrl: photoOf(sub) });
    expect(await copyJob(faceless)).toBeUndefined();
    expect(await copyJob(coded)).toBeUndefined();

    await auth.backfillGoogleAvatarCopies();

    const replayed = await copyJob(withPhoto);
    // Still the first run's job: a live job is never enqueued twice.
    expect(replayed?.timestamp).toBe(job?.timestamp);
  });
});
