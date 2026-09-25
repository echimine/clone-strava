import { Module, type DynamicModule } from "@nestjs/common";
import { NOTIFICATIONS_OPTIONS, type NotificationsModuleOptions } from "./notifications.constants.js";
import { NotificationsService } from "./notifications.service.js";

/**
 * `notifications` platform module (ADR-023 §1): owns no table, no
 * business rule, wraps `resend`. Every domain module and app may import
 * it (ADR-021 §2 "any layer ... may use analytics, storage").
 */
@Module({})
export class NotificationsModule {
  static forRoot(options: NotificationsModuleOptions): DynamicModule {
    return {
      module: NotificationsModule,
      providers: [{ provide: NOTIFICATIONS_OPTIONS, useValue: options }, NotificationsService],
      exports: [NotificationsService],
    };
  }
}
