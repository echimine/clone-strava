import { Injectable } from "@nestjs/common";
import type { AuditEntry, AuditPerson, AuditTargetType } from "@repo/contracts";
import { ActivitiesService } from "@repo/core/activities";
import type { AuditEntryRecord } from "@repo/core/audit";
import { AuthService } from "@repo/core/auth";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** The ids among `ids` that still exist. */
type ExistenceCheck = (ids: string[]) => Promise<Set<string>>;

/**
 * Turns Journal entries (ids only, ADR-038 §3) into what the backoffice shows: names of the
 * author and of the athlete concerned ("Compte supprimé" = `displayName: null`), and whether
 * the target still exists, so it can be linked. One batch call per module.
 *
 * A target type without an existence check here reads as gone: each area adds its own check
 * (comments, Media, report cases, Segments…) when its screens exist.
 */
@Injectable()
export class AuditEntryAssembler {
  private readonly existence: Partial<Record<AuditTargetType, ExistenceCheck>>;

  constructor(
    private readonly auth: AuthService,
    activities: ActivitiesService,
  ) {
    this.existence = {
      user: async (ids) => new Set((await auth.getPublicIdentities(ids)).map((identity) => identity.userId)),
      activity: async (ids) => new Set((await activities.getMany(ids)).map((activity) => activity.id)),
    };
  }

  async assemble(records: AuditEntryRecord[]): Promise<AuditEntry[]> {
    const nameOf = await this.people(records.flatMap((record) => [record.actorId, record.subjectUserId]));
    const existing = await this.existingTargets(records);
    return records.map((record) => ({
      id: record.id,
      createdAt: record.createdAt.toISOString(),
      action: record.action,
      actor: record.actorId === null ? null : nameOf(record.actorId),
      target: {
        type: record.targetType,
        id: record.targetId,
        exists: record.targetId !== null && (existing.get(record.targetType)?.has(record.targetId) ?? false),
      },
      subject: record.subjectUserId === null ? null : nameOf(record.subjectUserId),
      reason: record.reason,
      details: record.details,
      requestId: record.requestId,
    }));
  }

  /** Resolves user ids at once; a deleted account has no name. */
  async people(userIds: (string | null)[]): Promise<(userId: string) => AuditPerson> {
    const ids = [...new Set(userIds.filter((id): id is string => id !== null))];
    const identities = ids.length === 0 ? [] : await this.auth.getPublicIdentities(ids);
    const names = new Map(identities.map((identity) => [identity.userId, identity.name]));
    return (userId) => ({ id: userId, displayName: names.get(userId) ?? null });
  }

  private async existingTargets(records: AuditEntryRecord[]): Promise<Map<AuditTargetType, Set<string>>> {
    const idsByType = new Map<AuditTargetType, Set<string>>();
    for (const record of records) {
      // Every checked target type has uuid ids; anything else cannot exist.
      if (record.targetId !== null && UUID.test(record.targetId) && this.existence[record.targetType]) {
        idsByType.set(record.targetType, (idsByType.get(record.targetType) ?? new Set()).add(record.targetId));
      }
    }
    const checked = await Promise.all(
      [...idsByType].map(async ([type, ids]) => [type, await this.existence[type]!([...ids])] as const),
    );
    return new Map(checked);
  }
}
