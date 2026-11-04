import { randomUUID } from "node:crypto";
import { BullModule, getQueueToken } from "@nestjs/bullmq";
import type { INestApplicationContext } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import type { Queue } from "bullmq";
import { Redis } from "ioredis";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  EMAILS_QUEUE_NAME,
  SEND_EMAIL_JOB_NAME,
  sendEmailJobId,
  type SendEmailJob,
} from "@repo/contracts";
import { EmailJobs, EmailJobsModule, NotificationsService, type SendEmailParams, type SendEmailResult } from "@repo/core/notifications";
import { waitFor } from "../../testing/test-worker-app.js";
import { EmailsProcessorModule } from "./emails.module.js";

const TEST_REDIS_URL = "redis://127.0.0.1:6379";
const CONTACT_EMAIL = "contact@strava.test";
const ADMIN_ORIGIN = "https://admin.strava.test";

/** Resend is the third party (ADR-024 §2): a fake records what would have been sent. */
class FakeNotifications {
  readonly sent: SendEmailParams[] = [];
  /** Results to answer, in order, before answering `{ sent: true }`. */
  failures: SendEmailResult[] = [];

  async sendEmail(params: SendEmailParams): Promise<SendEmailResult> {
    this.sent.push(params);
    return this.failures.shift() ?? { sent: true };
  }
}

function banEmail(overrides: Partial<SendEmailJob> = {}): SendEmailJob {
  return {
    template: "user-banned",
    to: "lea@example.com",
    idempotencyKey: randomUUID(),
    userId: randomUUID(),
    data: { firstName: "Léa", reason: "Propos injurieux", until: null },
    ...overrides,
  } as SendEmailJob;
}

/** The `emails` queue (ADR-038 §4) on real Redis: enqueued by `EmailJobs`, sent by the worker. */
describe("send-email (integration)", () => {
  let app: INestApplicationContext;
  let connection: Redis;
  let notifications: FakeNotifications;

  const sentWithKey = (key: string) => () =>
    Promise.resolve(notifications.sent.find((email) => email.idempotencyKey === key));

  beforeAll(async () => {
    connection = new Redis(TEST_REDIS_URL, { maxRetriesPerRequest: null });
    notifications = new FakeNotifications();
    const moduleRef = await Test.createTestingModule({
      imports: [
        BullModule.forRoot({ connection, prefix: `test-${randomUUID()}` }),
        EmailJobsModule,
        EmailsProcessorModule.forRoot({ contactEmail: CONTACT_EMAIL, adminOrigin: ADMIN_ORIGIN }),
      ],
    })
      .overrideProvider(NotificationsService)
      .useValue(notifications)
      .compile();
    app = await moduleRef.init();
  });

  afterAll(async () => {
    await app?.close();
    await connection?.quit();
  });

  beforeEach(() => {
    notifications.failures = [];
  });

  it("renders the template and sends it to the athlete, the contact address as Reply-To", async () => {
    const job = banEmail();

    await app.get(EmailJobs).enqueue(job);
    const email = await waitFor(sentWithKey(job.idempotencyKey));

    expect(email).toMatchObject({
      to: "lea@example.com",
      subject: "Votre compte Nervo est suspendu",
      replyTo: CONTACT_EMAIL,
      idempotencyKey: job.idempotencyKey,
    });
    expect(email.html).toContain("Propos injurieux");
    expect(email.html).toContain(`${ADMIN_ORIGIN}/brand/nervo-wordmark-email.png`);
  });

  it("sends the Administrators' new-case e-mail without Reply-To", async () => {
    const job = {
      template: "report-case-opened",
      to: "admin@example.com",
      idempotencyKey: randomUUID(),
      userId: null,
      data: { targetType: "comment", reason: "spam", caseUrl: `${ADMIN_ORIGIN}/reports/${randomUUID()}` },
    } as SendEmailJob;

    await app.get(EmailJobs).enqueue(job);
    const email = await waitFor(sentWithKey(job.idempotencyKey));

    expect(email.to).toBe("admin@example.com");
    expect(email).not.toHaveProperty("replyTo");
  });

  it("enqueues one job per idempotency key", async () => {
    const job = banEmail();
    const emails = app.get(EmailJobs);

    await emails.enqueue(job);
    await emails.enqueue(job);
    await waitFor(sentWithKey(job.idempotencyKey));
    await new Promise((resolve) => setTimeout(resolve, 300));

    expect(notifications.sent.filter((email) => email.idempotencyKey === job.idempotencyKey)).toHaveLength(1);
  });

  it("refuses a job whose data does not match its template", async () => {
    const job = banEmail({ to: "not an e-mail" });

    await expect(app.get(EmailJobs).enqueue(job)).rejects.toThrow();
  });

  it("retries an e-mail Resend refused, under the same idempotency key", async () => {
    const job = banEmail();
    notifications.failures = [{ sent: false, error: "rate_limit_exceeded: Too many requests" }];
    const queue = app.get<Queue>(getQueueToken(EMAILS_QUEUE_NAME));

    await queue.add(SEND_EMAIL_JOB_NAME, job, {
      jobId: sendEmailJobId(job.idempotencyKey),
      attempts: 2,
      backoff: { type: "fixed", delay: 10 },
    });
    await waitFor(async () => ((await queue.getJob(sendEmailJobId(job.idempotencyKey)))?.finishedOn ? true : undefined));

    const attempts = notifications.sent.filter((email) => email.idempotencyKey === job.idempotencyKey);
    expect(attempts).toHaveLength(2);
    expect(await (await queue.getJob(sendEmailJobId(job.idempotencyKey)))?.getState()).toBe("completed");
  });

  it("fails for good a job whose payload is invalid", async () => {
    const queue = app.get<Queue>(getQueueToken(EMAILS_QUEUE_NAME));
    const jobId = `send-email-${randomUUID()}`;

    await queue.add(SEND_EMAIL_JOB_NAME, { template: "user-banned", to: "x" }, { jobId, attempts: 3, backoff: { type: "fixed", delay: 10 } });
    // `finishedOn` and `attemptsMade` come from the same read of the job: a state read after it
    // could already say `failed` while that read still showed the job running.
    const failed = await waitFor(async () => {
      const stored = await queue.getJob(jobId);
      return stored?.finishedOn && (await stored.getState()) === "failed" ? stored : undefined;
    });

    expect(failed.attemptsMade).toBe(1);
  });
});
