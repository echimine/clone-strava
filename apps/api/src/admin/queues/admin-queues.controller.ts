import { Controller, Get, HttpCode, HttpStatus, Param, Post, Query, UseGuards } from "@nestjs/common";
import { createZodDto, ZodResponse, ZodSerializerDto } from "nestjs-zod";
import {
  adminQueueJobDetailSchema,
  adminQueueJobListQuerySchema,
  adminQueueJobListResponseSchema,
  adminQueueListResponseSchema,
  adminQueueRetryFailedResponseSchema,
  type AdminQueueJobDetail,
  type AdminQueueJobListResponse,
  type AdminQueueListResponse,
  type AdminQueueName,
  type AdminQueueRetryFailedResponse,
} from "@repo/contracts";
import { AdminGuard } from "../../auth/admin.guard.js";
import { SessionGuard } from "../../auth/session.guard.js";
import { Audited, CurrentAuditDraft, type AuditDraft } from "../audit/audited.decorator.js";
import { AdminQueueNamePipe } from "./admin-queue-name.pipe.js";
import { AdminQueues } from "./admin-queues.js";

class AdminQueueListResponseDto extends createZodDto(adminQueueListResponseSchema) {}
class AdminQueueJobListQueryDto extends createZodDto(adminQueueJobListQuerySchema) {}
class AdminQueueJobListResponseDto extends createZodDto(adminQueueJobListResponseSchema) {}
class AdminQueueJobDetailDto extends createZodDto(adminQueueJobDetailSchema) {}
class AdminQueueRetryFailedResponseDto extends createZodDto(adminQueueRetryFailedResponseSchema) {}

/**
 * `/v1/admin/queues/*` (ADR-038 §14): the "Files" tab of the Jobs screen, over the queue
 * whitelist of `contracts` (`AdminQueueNamePipe`: `404 queue_not_found` for any other name).
 * Every action is recorded without a reason; no route removes a job. Bull Board stays off
 * production.
 */
@Controller("admin/queues")
@UseGuards(SessionGuard, AdminGuard)
export class AdminQueuesController {
  constructor(private readonly queues: AdminQueues) {}

  /** Counts by state, pause state and schedulers of every whitelisted queue. */
  @Get()
  @ZodResponse({ status: 200, type: AdminQueueListResponseDto })
  async list(): Promise<AdminQueueListResponse> {
    return { items: await this.queues.list() };
  }

  /** A queue's jobs in one state (`failed` by default), newest first. */
  @Get(":name/jobs")
  @ZodResponse({ status: 200, type: AdminQueueJobListResponseDto })
  jobs(
    @Param("name", AdminQueueNamePipe) name: AdminQueueName,
    @Query() query: AdminQueueJobListQueryDto,
  ): Promise<AdminQueueJobListResponse> {
    return this.queues.jobs(name, query);
  }

  /** One job with its stack traces and its data, read-only (`404 job_not_found`). */
  @Get(":name/jobs/:id")
  @ZodResponse({ status: 200, type: AdminQueueJobDetailDto })
  job(@Param("name", AdminQueueNamePipe) name: AdminQueueName, @Param("id") id: string): Promise<AdminQueueJobDetail> {
    return this.queues.job(name, id);
  }

  /**
   * Retries a failed job with its attempts reset. `409 retry_refused` for `process-activity`
   * and `import-activity` (« Retraiter » instead), `409 not_failed` for a job that has not failed.
   */
  @Post(":name/jobs/:id/retry")
  @HttpCode(HttpStatus.NO_CONTENT)
  @Audited("queue.job.retry", { reason: "none", targetParam: null })
  async retry(
    @Param("name", AdminQueueNamePipe) name: AdminQueueName,
    @Param("id") id: string,
    @CurrentAuditDraft() audit: AuditDraft,
  ): Promise<void> {
    await this.queues.retry(name, id);
    audit.targetId = `${name}/${id}`;
  }

  /** Retries every failed job of the queue but the refused ones; counts both. */
  @Post(":name/retry-failed")
  @HttpCode(HttpStatus.ACCEPTED)
  @Audited("queue.retry_failed", { reason: "none", targetParam: "name" })
  @ZodSerializerDto(AdminQueueRetryFailedResponseDto)
  async retryFailed(
    @Param("name", AdminQueueNamePipe) name: AdminQueueName,
    @CurrentAuditDraft() audit: AuditDraft,
  ): Promise<AdminQueueRetryFailedResponse> {
    const result = await this.queues.retryFailed(name);
    audit.details = { ...result };
    return result;
  }

  /** Workers stop taking the queue's jobs; the jobs stay. */
  @Post(":name/pause")
  @HttpCode(HttpStatus.NO_CONTENT)
  @Audited("queue.pause", { reason: "none", targetParam: "name" })
  async pause(@Param("name", AdminQueueNamePipe) name: AdminQueueName): Promise<void> {
    await this.queues.pause(name);
  }

  @Post(":name/resume")
  @HttpCode(HttpStatus.NO_CONTENT)
  @Audited("queue.resume", { reason: "none", targetParam: "name" })
  async resume(@Param("name", AdminQueueNamePipe) name: AdminQueueName): Promise<void> {
    await this.queues.resume(name);
  }
}
