import { Injectable, Logger } from "@nestjs/common";
import { OnEvent } from "@nestjs/event-emitter";
import {
  AUTH_ADMIN_ROLE_CHANGED_EVENT,
  AUTH_ADMIN_TWO_FACTOR_CHANGED_EVENT,
  type AuthAdminRoleChangedEvent,
  type AuthAdminTwoFactorChangedEvent,
} from "@repo/contracts";
import { AuditService } from "@repo/core/audit";

/**
 * Writes the Journal entries of Better Auth's hooks (ADR-038 §3): `auth` and `audit` are both
 * layer 0, so the `auth` module emits domain events and the API records them. Never throws.
 */
@Injectable()
export class AuthAuditListener {
  private readonly logger = new Logger(AuthAuditListener.name);

  constructor(private readonly audit: AuditService) {}

  @OnEvent(AUTH_ADMIN_TWO_FACTOR_CHANGED_EVENT, { async: true })
  async onTwoFactorChanged(event: AuthAdminTwoFactorChangedEvent): Promise<void> {
    await this.record({
      actorId: event.userId,
      action: event.enabled ? "admin.two_factor.enable" : "admin.two_factor.disable",
      targetId: event.userId,
      subjectUserId: event.userId,
    });
  }

  @OnEvent(AUTH_ADMIN_ROLE_CHANGED_EVENT, { async: true })
  async onRoleChanged(event: AuthAdminRoleChangedEvent): Promise<void> {
    await this.record({
      actorId: event.actorId,
      action: event.granted ? "user.role.grant" : "user.role.revoke",
      targetId: event.userId,
      subjectUserId: event.userId,
      details: { source: "better_auth" },
    });
  }

  private async record(entry: Parameters<AuditService["record"]>[0]): Promise<void> {
    try {
      await this.audit.record(entry);
    } catch (error) {
      this.logger.error(`Audit entry ${entry.action} for ${entry.targetId ?? ""} not written: ${String(error)}`);
    }
  }
}
