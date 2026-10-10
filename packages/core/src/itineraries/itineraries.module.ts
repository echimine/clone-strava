import { Module } from "@nestjs/common";
import { SportsModule } from "../sports/index.js";
import { ItinerariesService } from "./itineraries.service.js";
import { ItineraryGeometryRepository } from "./repositories/itinerary-geometry.repository.js";
import { ItineraryRepository } from "./repositories/itinerary.repository.js";
import { ItineraryMeasurementService } from "./services/itinerary-measurement.service.js";
import { ItinerarySaveService } from "./services/itinerary-save.service.js";
import { CreateItineraryUseCase } from "./use-cases/create-itinerary.use-case.js";
import { GetItineraryUseCase } from "./use-cases/get-itinerary.use-case.js";
import { ListItinerariesUseCase } from "./use-cases/list-itineraries.use-case.js";
import { PreviewItineraryMetricsUseCase } from "./use-cases/preview-itinerary-metrics.use-case.js";

/**
 * `itineraries` module (ADR-030 §4, ADR-021 §1, layer 1). Needs the global
 * `ElevationModule` registered by the app. Exports only its service.
 */
@Module({
  imports: [SportsModule],
  providers: [
    ItineraryRepository,
    ItineraryGeometryRepository,
    ItineraryMeasurementService,
    ItinerarySaveService,
    PreviewItineraryMetricsUseCase,
    CreateItineraryUseCase,
    GetItineraryUseCase,
    ListItinerariesUseCase,
    ItinerariesService,
  ],
  exports: [ItinerariesService],
})
export class ItinerariesModule {}
