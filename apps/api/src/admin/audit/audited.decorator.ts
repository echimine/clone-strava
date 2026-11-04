import {
  applyDecorators,
  createParamDecorator,
  type ExecutionContext,
  SetMetadata,
  UseInterceptors,
} from "@nestjs/common";
import type { AuditAction } from "@repo/contracts";
import { AuditInterceptor } from "./audit.interceptor.js";
import { AUDIT_DRAFT, AUDITED_METADATA, type AuditDraft, type AuditedOptions } from "./audit-metadata.js";

export type { AuditDraft, AuditedOptions } from "./audit-metadata.js";

/**
 * Declares an admin write and records it in the Journal after it succeeds (ADR-038 §3):
 *
 *     @Post(":id/ban")
 *     @Audited("user.ban", { reason: "required" })
 *     ban(@Param("id") id: string, @Body() body: BanBodyDto, @CurrentAuditDraft() audit: AuditDraft) {
 *       audit.details = { duration: body.duration };
 *       ...
 *     }
 *
 * - `reason`: `"required"` answers `400 reason_required` before anything runs when `body.reason`
 *   is missing or blank (a Sanction, ADR-038 §4); `"optional"` keeps it when given; `"none"`
 *   never reads it.
 * - The target type is the action's own (`AUDIT_ACTION_TARGETS`); its id is the route parameter
 *   `targetParam` (`"id"` by default, `null` for none). A `user` target is also the athlete
 *   concerned unless the handler says otherwise.
 * - The handler can complete the entry through `@CurrentAuditDraft()`: `subjectUserId`,
 *   `details`, or a `targetId` the route does not carry. `entryId` is the id the entry will
 *   get, e.g. the idempotency key of the e-mail job (ADR-038 §4).
 *
 * The entry is written after the handler returns, outside its transaction: a failed write is
 * logged as an error and the action stays done. A failed action records nothing.
 * `audit-coverage.spec.ts` fails when a non-`GET` route under `/v1/admin` lacks this decorator.
 */
export function Audited(action: AuditAction, options: AuditedOptions): MethodDecorator {
  return applyDecorators(
    SetMetadata(AUDITED_METADATA, { action, ...options }),
    UseInterceptors(AuditInterceptor),
  );
}

/** The entry `@Audited` is about to write, for the handler to complete. */
export const CurrentAuditDraft = createParamDecorator((_data: unknown, ctx: ExecutionContext): AuditDraft => {
  const request = ctx.switchToHttp().getRequest<{ [AUDIT_DRAFT]?: AuditDraft }>();
  const draft = request[AUDIT_DRAFT];
  if (!draft) {
    throw new Error("@CurrentAuditDraft() needs an @Audited route");
  }
  return draft;
});
