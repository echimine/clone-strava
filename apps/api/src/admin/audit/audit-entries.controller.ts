import { Controller, Get, Query, UseGuards } from "@nestjs/common";
import { createZodDto, ZodResponse } from "nestjs-zod";
import {
  auditActorListResponseSchema,
  auditEntryListQuerySchema,
  auditEntryListResponseSchema,
  type AuditActorListResponse,
  type AuditEntryListResponse,
} from "@repo/contracts";
import { AuditService } from "@repo/core/audit";
import { AdminGuard } from "../../auth/admin.guard.js";
import { SessionGuard } from "../../auth/session.guard.js";
import { AuditEntryAssembler } from "./audit-entry-assembler.js";

class AuditEntryListQueryDto extends createZodDto(auditEntryListQuerySchema) {}
class AuditEntryListResponseDto extends createZodDto(auditEntryListResponseSchema) {}
class AuditActorListResponseDto extends createZodDto(auditActorListResponseSchema) {}

/** The Journal (ADR-038 §3): read only, no endpoint ever changes or deletes an entry. */
@Controller("admin/audit-entries")
@UseGuards(SessionGuard, AdminGuard)
export class AuditEntriesController {
  constructor(
    private readonly audit: AuditService,
    private readonly assembler: AuditEntryAssembler,
  ) {}

  /** Newest first, filtered by author, action, athlete concerned and Paris days. */
  @Get()
  @ZodResponse({ status: 200, type: AuditEntryListResponseDto })
  async list(@Query() query: AuditEntryListQueryDto): Promise<AuditEntryListResponse> {
    const { page, pageSize, ...filter } = query;
    const entries = await this.audit.list(filter, { page, pageSize });
    return { ...entries, items: await this.assembler.assemble(entries.items) };
  }

  /** Everyone who authored an entry, former Administrators included. */
  @Get("actors")
  @ZodResponse({ status: 200, type: AuditActorListResponseDto })
  async actors(): Promise<AuditActorListResponse> {
    const ids = await this.audit.listActorIds();
    const nameOf = await this.assembler.people(ids);
    const items = ids.map(nameOf).sort((a, b) => (a.displayName ?? "~").localeCompare(b.displayName ?? "~", "fr"));
    return { items };
  }
}
