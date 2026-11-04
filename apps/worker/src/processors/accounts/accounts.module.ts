import { BullModule } from "@nestjs/bullmq";
import { type DynamicModule, Module } from "@nestjs/common";
import { ACCOUNTS_QUEUE_NAME } from "@repo/contracts";
import { AuditModule } from "@repo/core/audit";
import { SubscriptionsModule } from "@repo/core/subscriptions";
import { ACCOUNTS_PROCESSOR_OPTIONS, type AccountsProcessorOptions } from "./accounts.constants.js";
import { DeleteAccountProcessor } from "./delete-account.processor.js";
import { PostHogPersons } from "./posthog-persons.js";

/**
 * The `accounts` queue (ADR-038 §13): the cleanup of a deleted account outside the database,
 * enqueued by the API. Needs the app's `StorageModule`, `BullModule.forRoot` and, for the
 * RevenueCat customer, its global `RevenueCatModule` (without it that step is skipped).
 */
@Module({})
export class AccountsProcessorModule {
  static forRoot(options: AccountsProcessorOptions): DynamicModule {
    return {
      module: AccountsProcessorModule,
      imports: [AuditModule, SubscriptionsModule, BullModule.registerQueue({ name: ACCOUNTS_QUEUE_NAME })],
      providers: [{ provide: ACCOUNTS_PROCESSOR_OPTIONS, useValue: options }, PostHogPersons, DeleteAccountProcessor],
    };
  }
}
