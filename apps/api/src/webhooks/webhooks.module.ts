import { Module } from "@nestjs/common";
import { NotificationsModule } from "@repo/core/notifications";
import { SubscriptionsModule } from "@repo/core/subscriptions";
import { AuthModule } from "../auth/auth.module.js";
import { ConfigModule } from "../config/config.module.js";
import { loadConfig } from "../config/env.js";
import { RevenueCatWebhookController } from "./revenuecat.controller.js";
import { ResendWebhookController } from "./resend.controller.js";

// `forRoot(...)` is synchronous, same pattern as `AuthModule`/`AnalyticsModule`
// at the app level -- loaded once, at module-decoration time.
const config = loadConfig();

@Module({
  imports: [
    ConfigModule,
    SubscriptionsModule,
    // Direct sibling import, not routed through `AuthModule`: `webhooks`
    // only needs `NotificationsService` for signature verification, not
    // the whole Better Auth instance (architect decision, plan item 9/19).
    NotificationsModule.forRoot({
      apiKey: config.RESEND_API_KEY,
      webhookSecret: config.RESEND_WEBHOOK_SECRET,
    }),
    // For `AuthService`'s email-flagging method (`user` table ownership,
    // ADR-021).
    AuthModule,
  ],
  controllers: [RevenueCatWebhookController, ResendWebhookController],
})
export class WebhooksModule {}
