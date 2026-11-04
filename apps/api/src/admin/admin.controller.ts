import { Controller, Get, UseGuards } from "@nestjs/common";
import type { AdminAccessResponse } from "@repo/contracts";
import { AdminGuard } from "../auth/admin.guard.js";
import { SessionGuard } from "../auth/session.guard.js";

/**
 * `GET /v1/admin` (ADR-021 §1 "Not a module: admin"): answers `ok` when the session may use the
 * admin routes. Each admin area has its own controller under `src/admin/<area>/`, listed in
 * `admin.module.ts`; every write there is `@Audited` (ADR-038 §3).
 */
@Controller("admin")
@UseGuards(SessionGuard, AdminGuard)
export class AdminController {
  @Get()
  ping(): AdminAccessResponse {
    return { status: "ok" };
  }
}
