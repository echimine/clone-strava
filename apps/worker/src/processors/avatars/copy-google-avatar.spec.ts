import { randomUUID } from "node:crypto";
import { getQueueToken } from "@nestjs/bullmq";
import type { JobsOptions, Queue } from "bullmq";
import sharp from "sharp";
import { afterAll, afterEach, beforeAll, describe, expect, it, vi, type MockInstance } from "vitest";
import {
  AVATARS_QUEUE_NAME,
  COPY_GOOGLE_AVATAR_JOB_NAME,
  avatarKey,
  copyGoogleAvatarJobId,
  userAvatarsPrefix,
  type CopyGoogleAvatarJob,
} from "@repo/contracts";
import { bootstrapTestWorkerApp, waitFor, type TestWorkerApp } from "../../testing/test-worker-app.js";

const GOOGLE_PHOTO = "https://lh3.googleusercontent.com/a/ACg8ocTestPhoto=s96-c";
/** Fast retries, so the "gives up" cases finish within the test. */
const FAST_RETRY: JobsOptions = { attempts: 2, backoff: { type: "fixed", delay: 10 } };

/**
 * The Google photo copied as the Avatar (ADR-037 §2) on real Postgres and Redis, the bucket in
 * memory. Google's servers are the only faked `fetch`: they answer with a photo made here.
 */
describe("copy-google-avatar (integration)", () => {
  let ctx: TestWorkerApp;
  let photos: Map<string, Response | (() => Response)>;
  let fetchSpy: MockInstance<typeof fetch>;
  const users: string[] = [];

  async function sql(text: string, params: unknown[]) {
    return (await ctx.db.$client.query(text, params)).rows;
  }

  async function googleAccount(): Promise<string> {
    const id = randomUUID();
    users.push(id);
    await sql('insert into "user" (id, name, email) values ($1, $2, $3)', [id, "Jeanne Martin", `${id}@test.local`]);
    return id;
  }

  async function avatarKeyOf(userId: string): Promise<string | null> {
    const [row] = await sql("select avatar_key from users.user_profile where user_id = $1", [userId]);
    return (row?.avatar_key as string | null | undefined) ?? null;
  }

  const avatarsOf = (userId: string) =>
    [...ctx.storage.objects.keys()].filter((key) => key.startsWith(userAvatarsPrefix(userId)));

  const googleCalls = () =>
    fetchSpy.mock.calls.filter(([input]) => String(input instanceof Request ? input.url : input).includes("googleusercontent")).length;

  function photo(width: number, height: number): Promise<Buffer> {
    return sharp({ create: { width, height, channels: 3, background: "#d14" } }).png().toBuffer();
  }

  function serve(url: string, response: Response | (() => Response)): void {
    photos.set(url, response);
  }

  function queue(): Queue<CopyGoogleAvatarJob> {
    return ctx.app.get<Queue<CopyGoogleAvatarJob>>(getQueueToken(AVATARS_QUEUE_NAME));
  }

  /** Runs one copy through the queue and waits for its end state. */
  async function copy(userId: string, imageUrl = GOOGLE_PHOTO, options: JobsOptions = FAST_RETRY) {
    const job = await queue().add(COPY_GOOGLE_AVATAR_JOB_NAME, { userId, imageUrl }, {
      ...options,
      jobId: `${copyGoogleAvatarJobId(userId)}-${randomUUID()}`,
    });
    return waitFor(async () => {
      const state = await job.getState();
      return state === "completed" || state === "failed" ? state : undefined;
    });
  }

  beforeAll(async () => {
    ctx = await bootstrapTestWorkerApp();
  }, 30_000);

  beforeAll(() => {
    photos = new Map();
    const realFetch = globalThis.fetch;
    fetchSpy = vi.spyOn(globalThis, "fetch").mockImplementation((input, init) => {
      const url = input instanceof Request ? input.url : String(input);
      if (!url.startsWith("https://lh3.googleusercontent.com/")) {
        return realFetch(input, init);
      }
      const served = photos.get(url);
      const response = typeof served === "function" ? served() : served;
      return Promise.resolve(response ?? new Response("not found", { status: 404 }));
    });
  });

  afterEach(() => {
    photos.clear();
    fetchSpy.mockClear();
  });

  afterAll(async () => {
    fetchSpy.mockRestore();
    if (users.length > 0) {
      await sql('delete from "user" where id = any($1)', [users]);
    }
    await ctx?.close();
  });

  it("stores a 512×512 JPEG as the Avatar of a new Google account", async () => {
    const userId = await googleAccount();
    // Google serves the same photo at any size: the copy asks for 512 px, not the token's 96.
    serve("https://lh3.googleusercontent.com/a/ACg8ocTestPhoto=s512-c", new Response(await photo(640, 480)));

    expect(await copy(userId)).toBe("completed");

    const key = await avatarKeyOf(userId);
    expect(key).toMatch(new RegExp(`^${userAvatarsPrefix(userId)}[0-9a-f-]{36}\\.jpg$`));
    expect(avatarsOf(userId)).toEqual([key]);
    const metadata = await sharp(ctx.storage.objects.get(key!)).metadata();
    expect(metadata).toMatchObject({ format: "jpeg", width: 512, height: 512 });
  });

  it("copies a photo outside Google's sizing scheme as is (Google's letter image)", async () => {
    const userId = await googleAccount();
    const letter = "https://lh3.googleusercontent.com/a/default-user";
    serve(letter, new Response(await photo(100, 100)));

    expect(await copy(userId, letter)).toBe("completed");

    const key = await avatarKeyOf(userId);
    expect(await sharp(ctx.storage.objects.get(key!)).metadata()).toMatchObject({ width: 512, height: 512 });
  });

  it("keeps an Avatar already set, without downloading anything", async () => {
    const userId = await googleAccount();
    const own = avatarKey(userId, randomUUID());
    ctx.storage.objects.set(own, new Uint8Array([0xff, 0xd8]));
    await sql("insert into users.user_profile (user_id, avatar_key) values ($1, $2)", [userId, own]);
    serve("https://lh3.googleusercontent.com/a/ACg8ocTestPhoto=s512-c", new Response(await photo(96, 96)));

    expect(await copy(userId)).toBe("completed");

    expect(await avatarKeyOf(userId)).toBe(own);
    expect(avatarsOf(userId)).toEqual([own]);
    expect(googleCalls()).toBe(0);
  });

  it("copies nothing the second time: a replay keeps the first copy", async () => {
    const userId = await googleAccount();
    const body = await photo(96, 96);
    serve("https://lh3.googleusercontent.com/a/ACg8ocTestPhoto=s512-c", () => new Response(body));
    expect(await copy(userId)).toBe("completed");
    const first = await avatarKeyOf(userId);

    expect(await copy(userId)).toBe("completed");

    expect(await avatarKeyOf(userId)).toBe(first);
    expect(avatarsOf(userId)).toEqual([first]);
  });

  it("retries, then gives up and leaves no Avatar when Google keeps failing", async () => {
    const userId = await googleAccount();
    serve("https://lh3.googleusercontent.com/a/ACg8ocTestPhoto=s512-c", () => new Response("busy", { status: 503 }));

    expect(await copy(userId)).toBe("failed");

    expect(await avatarKeyOf(userId)).toBeNull();
    expect(avatarsOf(userId)).toEqual([]);
    expect(googleCalls()).toBe(2);
  });

  it("gives up at once on a photo that is gone or not an image", async () => {
    const gone = await googleAccount();
    const broken = await googleAccount();
    const brokenUrl = "https://lh3.googleusercontent.com/a/broken";
    serve(brokenUrl, () => new Response("<html></html>", { headers: { "content-type": "text/html" } }));

    expect(await copy(gone)).toBe("failed");
    expect(await copy(broken, brokenUrl)).toBe("failed");

    expect(await avatarKeyOf(gone)).toBeNull();
    expect(await avatarKeyOf(broken)).toBeNull();
    expect(googleCalls()).toBe(2);
  });
});
