import { Module } from "@nestjs/common";
import { SubscriptionsModule } from "@repo/core/subscriptions";
import { ConfigModule } from "../config/config.module.js";
import { RevenueCatWebhookController } from "./revenuecat.controller.js";

@Module({
  imports: [ConfigModule, SubscriptionsModule],
  controllers: [RevenueCatWebhookController],
})
export class WebhooksModule {}
