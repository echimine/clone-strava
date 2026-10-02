import { Module, type DynamicModule } from "@nestjs/common";
import { GEOCODING_OPTIONS, type GeocodingModuleOptions } from "./geocoding.constants.js";
import { GeocodingService } from "./geocoding.service.js";

/**
 * `geocoding` platform module (ADR-029, ADR-021 §1): global, registered
 * once by each app. Without an access token it is a no-op.
 */
@Module({})
export class GeocodingModule {
  static forRoot(options: GeocodingModuleOptions): DynamicModule {
    return {
      module: GeocodingModule,
      global: true,
      providers: [{ provide: GEOCODING_OPTIONS, useValue: options }, GeocodingService],
      exports: [GeocodingService],
    };
  }
}
