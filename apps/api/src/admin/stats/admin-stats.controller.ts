import { Controller, Get, Query, UseGuards } from "@nestjs/common";
import { createZodDto, ZodResponse } from "nestjs-zod";
import {
  adminGrowthQuerySchema,
  adminGrowthStatsSchema,
  adminTodoStatsSchema,
  type AdminGrowthStats,
  type AdminTodoStats,
} from "@repo/contracts";
import { AdminGuard } from "../../auth/admin.guard.js";
import { SessionGuard } from "../../auth/session.guard.js";
import { AdminStatsAssembler } from "./admin-stats.assembler.js";

class AdminTodoStatsDto extends createZodDto(adminTodoStatsSchema) {}
class AdminGrowthQueryDto extends createZodDto(adminGrowthQuerySchema) {}
class AdminGrowthStatsDto extends createZodDto(adminGrowthStatsSchema) {}

/** The backoffice dashboard (ADR-038 §15): read only, nothing goes to the Journal. */
@Controller("admin/stats")
@UseGuards(SessionGuard, AdminGuard)
export class AdminStatsController {
  constructor(private readonly stats: AdminStatsAssembler) {}

  /** "À traiter": open Reports, failed Activities, imports and jobs, Efforts to review. */
  @Get("todo")
  @ZodResponse({ status: 200, type: AdminTodoStatsDto })
  todo(): Promise<AdminTodoStats> {
    return this.stats.todo();
  }

  /** "Croissance" over the last 7, 30 or 90 Paris days, against the previous period. */
  @Get("growth")
  @ZodResponse({ status: 200, type: AdminGrowthStatsDto })
  growth(@Query() query: AdminGrowthQueryDto): Promise<AdminGrowthStats> {
    return this.stats.growth(query.period);
  }
}
