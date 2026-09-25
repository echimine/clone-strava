export { NotificationsModule } from "./notifications.module.js";
export { NotificationsService, type SendAuthEmailParams, type ResendWebhookHeaders } from "./notifications.service.js";
export type { NotificationsModuleOptions } from "./notifications.constants.js";
export { renderVerifyEmail, renderResetPasswordEmail, renderAdminOtpEmail } from "./emails/index.js";
