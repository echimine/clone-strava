import { Injectable } from "@nestjs/common";
import type {
  CreateItineraryRequest,
  Itinerary,
  ItineraryGeometry,
  ItineraryMetrics,
  ListItinerariesQuery,
  ListItinerariesResponse,
} from "@repo/contracts";
import { CreateItineraryUseCase, type CreateItineraryResult } from "./use-cases/create-itinerary.use-case.js";
import { GetItineraryUseCase } from "./use-cases/get-itinerary.use-case.js";
import { ListItinerariesUseCase } from "./use-cases/list-itineraries.use-case.js";
import { PreviewItineraryMetricsUseCase } from "./use-cases/preview-itinerary-metrics.use-case.js";

/** Facade of the `itineraries` module (ADR-021 §6, ADR-030 §4). */
@Injectable()
export class ItinerariesService {
  constructor(
    private readonly previewMetricsUseCase: PreviewItineraryMetricsUseCase,
    private readonly createUseCase: CreateItineraryUseCase,
    private readonly getUseCase: GetItineraryUseCase,
    private readonly listUseCase: ListItinerariesUseCase,
  ) {}

  previewMetrics(geometry: ItineraryGeometry): Promise<ItineraryMetrics> {
    return this.previewMetricsUseCase.execute(geometry);
  }

  create(userId: string, request: CreateItineraryRequest): Promise<CreateItineraryResult> {
    return this.createUseCase.execute(userId, request);
  }

  get(userId: string, itineraryId: string): Promise<Itinerary> {
    return this.getUseCase.execute(userId, itineraryId);
  }

  list(userId: string, query: ListItinerariesQuery): Promise<ListItinerariesResponse> {
    return this.listUseCase.execute(userId, query);
  }
}
