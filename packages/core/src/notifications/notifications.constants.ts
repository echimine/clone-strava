export interface NotificationsModuleOptions {
  apiKey: string;
  webhookSecret: string;
}

export const NOTIFICATIONS_OPTIONS = Symbol("NOTIFICATIONS_OPTIONS");
