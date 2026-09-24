import { Controller, Get, UseGuards } from "@nestjs/common";
import { AdminGuard } from "../auth/admin.guard.js";
import { SessionGuard } from "../auth/session.guard.js";

/**
 * `/v1/admin/*` placeholder (ADR-021 §1 "Not a module: admin"): admin
 * endpoints live here and call the services of the relevant domain modules
 * directly, e.g. `POST /v1/admin/activities/:id/reprocess` ->
 * `ActivitiesService.reprocess(id)` (ADR-019 §6).
 */
@Controller("admin")
@UseGuards(SessionGuard, AdminGuard)
export class AdminController {
  @Get()
  ping(): { status: "ok" } {
    return { status: "ok" };
  }
}
