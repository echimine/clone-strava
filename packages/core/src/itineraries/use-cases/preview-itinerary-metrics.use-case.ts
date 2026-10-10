import { Injectable } from "@nestjs/common";
import type { ItineraryGeometry, ItineraryMetrics } from "@repo/contracts";
import { ItineraryMeasurementService } from "../services/itinerary-measurement.service.js";

/**
 * `POST /v1/itineraries/metrics-preview` (ADR-030 §3, §6): the save
 * computation on the full track, without writing anything.
 */
@Injectable()
export class PreviewItineraryMetricsUseCase {
  constructor(private readonly measurement: ItineraryMeasurementService) {}

  async execute(geometry: ItineraryGeometry): Promise<ItineraryMetrics> {
    return (await this.measurement.measure(geometry)).metrics;
  }
}
