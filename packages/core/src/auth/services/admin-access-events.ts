import type { EventEmitter2 } from "@nestjs/event-emitter";
import { eq } from "drizzle-orm";
import {
  AUTH_ADMIN_ROLE_CHANGED_EVENT,
  AUTH_ADMIN_TWO_FACTOR_CHANGED_EVENT,
  type AuthAdminRoleChangedEvent,
  type AuthAdminTwoFactorChangedEvent,
} from "@repo/contracts";
import { schema, type Database } from "@repo/db";

/** The part of Better Auth's endpoint context the `user.update` hooks read. */
interface HookContext {
  /** Set only when the endpoint was reached over HTTP, not by a server-side `auth.api.*` call. */
  request?: Request;
  body?: unknown;
  context?: { session?: { user?: { id?: string } } | null };
}

interface AccessSnapshot {
  userId: string;
  role: string | null;
  twoFactorEnabled: boolean | null;
}

/**
 * Turns `user` updates that change admin access into domain events (ADR-038 §3), from Better
 * Auth's `databaseHooks.user.update`:
 * - an Administrator's `twoFactorEnabled` turned on or off (`/two-factor/*`);
 * - the `admin` role granted or removed through Better Auth's own HTTP routes
 *   (`/api/auth/admin/set-role`…). A server-side `auth.api.setRole` call is the API's own
 *   backoffice route, which records itself.
 *
 * `before` reads the user's access as it was (the update's payload has no id: the user is the
 * body's `userId` or the session's), `after` compares. Updates outside an endpoint (scripts,
 * `internalAdapter` in a job) have no context and emit nothing.
 */
export class AdminAccessEvents {
  private readonly pending = new WeakMap<object, AccessSnapshot>();

  constructor(
    private readonly db: Database,
    private readonly events: EventEmitter2 | null,
  ) {}

  async beforeUserUpdate(data: Record<string, unknown>, ctx: HookContext | null): Promise<void> {
    if (!this.events || !ctx || !("twoFactorEnabled" in data || "role" in data)) {
      return;
    }
    const body = ctx.body as { userId?: unknown } | undefined;
    const userId = typeof body?.userId === "string" ? body.userId : ctx.context?.session?.user?.id;
    if (!userId) {
      return;
    }
    const [previous] = await this.db
      .select({ role: schema.user.role, twoFactorEnabled: schema.user.twoFactorEnabled })
      .from(schema.user)
      .where(eq(schema.user.id, userId));
    if (previous) {
      this.pending.set(ctx, { userId, ...previous });
    }
  }

  afterUserUpdate(
    user: { id: string; role?: string | null; twoFactorEnabled?: boolean | null },
    ctx: HookContext | null,
  ): void {
    const previous = ctx ? this.pending.get(ctx) : undefined;
    if (!this.events || !ctx || !previous || previous.userId !== user.id) {
      return;
    }
    this.pending.delete(ctx);
    const isAdmin = user.role === "admin";
    const twoFactorEnabled = user.twoFactorEnabled === true;
    if (isAdmin && twoFactorEnabled !== (previous.twoFactorEnabled === true)) {
      const event: AuthAdminTwoFactorChangedEvent = { userId: user.id, enabled: twoFactorEnabled };
      this.events.emit(AUTH_ADMIN_TWO_FACTOR_CHANGED_EVENT, event);
    }
    if (ctx.request && isAdmin !== (previous.role === "admin")) {
      const event: AuthAdminRoleChangedEvent = {
        userId: user.id,
        actorId: ctx.context?.session?.user?.id ?? null,
        granted: isAdmin,
      };
      this.events.emit(AUTH_ADMIN_ROLE_CHANGED_EVENT, event);
    }
  }
}
