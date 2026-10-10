import { Module } from "@nestjs/common";
import { ItinerariesService } from "./itineraries.service.js";
import { ItineraryMeasurementService } from "./services/itinerary-measurement.service.js";
import { PreviewItineraryMetricsUseCase } from "./use-cases/preview-itinerary-metrics.use-case.js";

/**
 * `itineraries` module (ADR-030 §4, ADR-021 §1, layer 1). Needs the global
 * `ElevationModule` registered by the app. Exports only its service.
 */
@Module({
  providers: [ItineraryMeasurementService, PreviewItineraryMetricsUseCase, ItinerariesService],
  exports: [ItinerariesService],
})
export class ItinerariesModule {}
