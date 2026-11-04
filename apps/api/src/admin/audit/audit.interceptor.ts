import { randomUUID } from "node:crypto";
import {
  BadRequestException,
  type CallHandler,
  type ExecutionContext,
  Injectable,
  Logger,
  type NestInterceptor,
} from "@nestjs/common";
import { Reflector } from "@nestjs/core";
import type { Request } from "express";
import { concatMap, type Observable } from "rxjs";
import {
  ADMIN_REASON_REQUIRED_CODE,
  AUDIT_ACTION_TARGETS,
  adminOptionalReasonSchema,
  adminReasonSchema,
} from "@repo/contracts";
import { AuditService } from "@repo/core/audit";
import type { AuthenticatedUser } from "../../auth/session.guard.js";
import { AUDIT_DRAFT, AUDITED_METADATA, type AuditDraft, type AuditedMetadata } from "./audit-metadata.js";

type AuditedRequest = Request & { id?: unknown; user?: AuthenticatedUser; [AUDIT_DRAFT]?: AuditDraft };

/**
 * Writes the audit entry of an `@Audited` route once its handler has succeeded (ADR-038 §3).
 * Runs after the guards and before the pipes, so a missing required reason answers
 * `400 reason_required` before the body is validated.
 */
@Injectable()
export class AuditInterceptor implements NestInterceptor {
  private readonly logger = new Logger(AuditInterceptor.name);

  constructor(
    private readonly reflector: Reflector,
    private readonly audit: AuditService,
  ) {}

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const metadata = this.reflector.get<AuditedMetadata | undefined>(AUDITED_METADATA, context.getHandler());
    if (!metadata) {
      return next.handle();
    }
    const request = context.switchToHttp().getRequest<AuditedRequest>();
    const reason = readReason(metadata, request.body);
    const draft: AuditDraft = { entryId: randomUUID() };
    request[AUDIT_DRAFT] = draft;

    return next.handle().pipe(
      concatMap(async (result: unknown) => {
        await this.write(metadata, request, draft, reason);
        return result;
      }),
    );
  }

  private async write(
    metadata: AuditedMetadata,
    request: AuditedRequest,
    draft: AuditDraft,
    reason: string | null,
  ): Promise<void> {
    let action = draft.action ?? metadata.action;
    if (AUDIT_ACTION_TARGETS[action] !== AUDIT_ACTION_TARGETS[metadata.action]) {
      this.logger.error(`@Audited("${metadata.action}") cannot record ${action}: another target type`);
      action = metadata.action;
    }
    const targetType = AUDIT_ACTION_TARGETS[action];
    const param = metadata.targetParam === undefined ? "id" : metadata.targetParam;
    const routeValue = param === null ? undefined : request.params[param];
    const routeTargetId = routeValue === undefined ? null : [routeValue].flat().join("/");
    const targetId = draft.targetId === undefined ? routeTargetId : draft.targetId;
    const subjectUserId =
      draft.subjectUserId === undefined ? (targetType === "user" ? targetId : null) : draft.subjectUserId;
    try {
      await this.audit.record({
        id: draft.entryId,
        actorId: request.user?.userId ?? null,
        action,
        targetType,
        targetId,
        subjectUserId,
        reason: draft.reason === undefined ? reason : draft.reason,
        details: draft.details ?? null,
        requestId: request.id === undefined ? null : String(request.id),
      });
    } catch (error) {
      // ADR-038 §3: no shared transaction; the action stays done, the gap is logged.
      this.logger.error(
        `Audit entry ${draft.entryId} (${action} ${targetId ?? ""}) not written: ${String(error)}`,
      );
    }
  }
}

/** The reason to record, or `400 reason_required` for a Sanction without one. */
function readReason(metadata: AuditedMetadata, body: unknown): string | null {
  if (metadata.reason === "none") {
    return null;
  }
  const raw = typeof body === "object" && body !== null ? (body as { reason?: unknown }).reason : undefined;
  if (metadata.reason === "optional") {
    const parsed = adminOptionalReasonSchema.safeParse(raw);
    return parsed.success ? (parsed.data ?? null) : null;
  }
  const parsed = adminReasonSchema.safeParse(raw);
  if (!parsed.success) {
    throw new BadRequestException({ code: ADMIN_REASON_REQUIRED_CODE, message: "Le motif est obligatoire" });
  }
  return parsed.data;
}
