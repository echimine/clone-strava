import { Body, Controller, HttpCode, HttpStatus, Post, UseGuards } from "@nestjs/common";
import { createZodDto, ZodResponse } from "nestjs-zod";
import {
  itineraryMetricsPreviewRequestSchema,
  itineraryMetricsSchema,
  type ItineraryMetrics,
} from "@repo/contracts";
import { ItinerariesService } from "@repo/core/itineraries";
import { SessionGuard } from "../auth/session.guard.js";

class ItineraryMetricsPreviewRequestDto extends createZodDto(itineraryMetricsPreviewRequestSchema) {}
class ItineraryMetricsDto extends createZodDto(itineraryMetricsSchema) {}

/** `/v1/itineraries` (ADR-030 §6): the athlete's private Itineraries. */
@Controller("itineraries")
@UseGuards(SessionGuard)
export class ItinerariesController {
  constructor(private readonly itineraries: ItinerariesService) {}

  /**
   * Distance and elevation gain a save would store for these Waypoints
   * and Legs; writes nothing. `503` (retryable) when an elevation provider
   * fails. Only the global throttler limit applies.
   */
  @Post("metrics-preview")
  @HttpCode(HttpStatus.OK)
  @ZodResponse({ status: 200, type: ItineraryMetricsDto })
  previewMetrics(@Body() body: ItineraryMetricsPreviewRequestDto): Promise<ItineraryMetrics> {
    return this.itineraries.previewMetrics(body);
  }
}
