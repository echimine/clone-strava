import { Injectable, Logger } from "@nestjs/common";
import { OnEvent } from "@nestjs/event-emitter";
import { NERVO_ADMIN_ORIGIN, REPORT_CASE_OPENED_EVENT, type ReportCaseOpenedEvent } from "@repo/contracts";
import { AuthService } from "@repo/core/auth";
import { EmailJobs } from "@repo/core/notifications";

/** The case in the backoffice: the e-mail's link. */
export function reportCaseUrl(caseId: string, adminOrigin = NERVO_ADMIN_ORIGIN): string {
  return new URL(`/reports/${caseId}`, adminOrigin).href;
}

/**
 * E-mails every Administrator when a Report opens a case (ADR-038 §10), never on later Reports:
 * one `send-email` job of the `emails` queue per Administrator, after the Report's commit
 * (`moderation.case.opened`), so it never weighs on `POST /v1/reports`. Target type, reason and
 * link only, never a copy of the content. Never throws: a failure is logged.
 */
@Injectable()
export class ReportCaseAlerts {
  private readonly logger = new Logger(ReportCaseAlerts.name);

  constructor(
    private readonly auth: AuthService,
    private readonly emails: EmailJobs,
  ) {}

  @OnEvent(REPORT_CASE_OPENED_EVENT, { async: true })
  async onCaseOpened(event: ReportCaseOpenedEvent): Promise<void> {
    let admins: { userId: string; email: string }[];
    try {
      admins = await this.auth.listAdminRecipients();
    } catch (error) {
      this.logger.error(`Report case ${event.caseId}: Administrators not read, no e-mail: ${String(error)}`);
      return;
    }
    await Promise.all(
      admins.map(async (admin) => {
        try {
          await this.emails.enqueue({
            template: "report-case-opened",
            to: admin.email,
            // One e-mail per case and Administrator, whatever the retries.
            idempotencyKey: `report-case-${event.caseId}-${admin.userId}`,
            userId: null,
            data: { targetType: event.targetType, reason: event.reason, caseUrl: reportCaseUrl(event.caseId) },
          });
        } catch (error) {
          this.logger.error(
            `Report case ${event.caseId}: e-mail to Administrator ${admin.userId} not enqueued: ${String(error)}`,
          );
        }
      }),
    );
  }
}
