import { Module, type DynamicModule } from "@nestjs/common";
import { ELEVATION_OPTIONS, type ElevationModuleOptions } from "./elevation.constants.js";
import { ElevationService } from "./elevation.service.js";

/**
 * `elevation` platform module (ADR-030 §3, §4, ADR-021 §1): global,
 * registered once by `apps/api`. IGN and Open-Meteo need no key.
 */
@Module({})
export class ElevationModule {
  static forRoot(options: ElevationModuleOptions): DynamicModule {
    return {
      module: ElevationModule,
      global: true,
      providers: [{ provide: ELEVATION_OPTIONS, useValue: options }, ElevationService],
      exports: [ElevationService],
    };
  }
}
