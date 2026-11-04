import { Module } from "@nestjs/common";
import { ActivitiesModule } from "@repo/core/activities";
import { AuditModule } from "@repo/core/audit";
import { EngagementModule } from "@repo/core/engagement";
import { ModerationModule } from "@repo/core/moderation";
import { SegmentsModule } from "@repo/core/segments";
import { UsersModule } from "@repo/core/users";
import { AuthModule } from "../auth/auth.module.js";
import { IdentitiesModule } from "../identities/identities.module.js";
import { MediaAssembler } from "../media/media-assembler.js";
import { AdminActivitiesController } from "./activities/admin-activities.controller.js";
import { AdminActivityAssembler } from "./activities/admin-activity-assembler.js";
import { AdminCommentsController } from "./comments/admin-comments.controller.js";
import { AdminFailureAssembler } from "./failures/admin-failure-assembler.js";
import { AdminFailuresController } from "./failures/admin-failures.controller.js";
import { AdminPremiumAssembler } from "./premium/admin-premium-assembler.js";
import { AdminPremiumController } from "./premium/admin-premium.controller.js";
import { AdminQueuesController } from "./queues/admin-queues.controller.js";
import { AdminQueuesModule } from "./queues/admin-queues.module.js";
import { SanctionNotices } from "./sanctions/sanction-notices.js";
import { AdminActivityImportsController } from "./activity-imports/admin-activity-imports.controller.js";
import { AdminController } from "./admin.controller.js";
import { AuditEntriesController } from "./audit/audit-entries.controller.js";
import { AuditEntryAssembler } from "./audit/audit-entry-assembler.js";
import { AuthAuditListener } from "./audit/auth-audit.listener.js";
import { AdminStatsController } from "./stats/admin-stats.controller.js";
import { ADMIN_STATS_IMPORTS, ADMIN_STATS_PROVIDERS } from "./stats/admin-stats.providers.js";
import { AdminUserAssembler } from "./users/admin-user-assembler.js";
import { AdminUsersController } from "./users/admin-users.controller.js";

/**
 * `/v1/admin/*` (ADR-021 §1 "Not a module: admin", ADR-038 §1): one controller per area under
 * `src/admin/<area>/`, each listed here. `AuditModule` serves `@Audited` on every admin write.
 */
@Module({
  imports: [
    AuthModule,
    AuditModule,
    ActivitiesModule,
    EngagementModule,
    SegmentsModule,
    ModerationModule,
    UsersModule,
    IdentitiesModule,
    AdminQueuesModule,
    ...ADMIN_STATS_IMPORTS,
  ],
  controllers: [
    AdminController,
    AdminActivityImportsController,
    AuditEntriesController,
    AdminActivitiesController,
    AdminCommentsController,
    AdminFailuresController,
    AdminQueuesController,
    AdminStatsController,
    AdminUsersController,
    AdminPremiumController,
  ],
  providers: [
    AuditEntryAssembler,
    AuthAuditListener,
    AdminActivityAssembler,
    MediaAssembler,
    SanctionNotices,
    AdminUserAssembler,
    AdminPremiumAssembler,
    AdminFailureAssembler,
    ...ADMIN_STATS_PROVIDERS,
  ],
})
export class AdminModule {}
