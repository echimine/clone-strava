export { NotificationsModule } from "./notifications.module.js";
export {
  NotificationsService,
  type SendEmailParams,
  type SendEmailResult,
  type ResendWebhookHeaders,
} from "./notifications.service.js";
export type { NotificationsModuleOptions } from "./notifications.constants.js";
export { EmailJobsModule } from "./email-jobs.module.js";
export { EmailJobs } from "./email-jobs.js";
export {
  emailWordmarkUrl,
  renderVerifyEmail,
  renderResetPasswordEmail,
  renderAdminOtpEmail,
  renderSignInCodeEmail,
  renderEmailJob,
  type EmailRenderContext,
  type RenderedEmail,
} from "./emails/index.js";
