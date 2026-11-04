import { Module, type DynamicModule } from "@nestjs/common";
import { REVENUECAT_OPTIONS, type RevenueCatOptions } from "./revenuecat.constants.js";

/**
 * Configures RevenueCat's API v2 for `SubscriptionsModule` (ADR-038 §12), once per app (API and
 * worker). Global, so every `SubscriptionsModule` import sees it; an app or a test that does not
 * register it gets a read-only Premium (« RevenueCat non configuré »).
 */
@Module({})
export class RevenueCatModule {
  static forRoot(options: RevenueCatOptions): DynamicModule {
    return {
      module: RevenueCatModule,
      global: true,
      providers: [{ provide: REVENUECAT_OPTIONS, useValue: options }],
      exports: [REVENUECAT_OPTIONS],
    };
  }
}
