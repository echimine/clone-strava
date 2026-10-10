import { Injectable } from "@nestjs/common";
import type { ItineraryGeometry, ItineraryMetrics } from "@repo/contracts";
import { PreviewItineraryMetricsUseCase } from "./use-cases/preview-itinerary-metrics.use-case.js";

/** Facade of the `itineraries` module (ADR-021 §6, ADR-030 §4). */
@Injectable()
export class ItinerariesService {
  constructor(private readonly previewMetricsUseCase: PreviewItineraryMetricsUseCase) {}

  previewMetrics(geometry: ItineraryGeometry): Promise<ItineraryMetrics> {
    return this.previewMetricsUseCase.execute(geometry);
  }
}
