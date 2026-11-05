import { Controller, Get, Header, HttpStatus, NotFoundException, Redirect } from "@nestjs/common";
import { ApiResponse } from "@nestjs/swagger";
import { SegmentsService } from "@repo/core/segments";

/** The pre-signed URL outlives the cached redirect by far. */
const SIGNED_URL_TTL_S = 3600;
const CACHE_CONTROL = "public, max-age=900";

/**
 * The ODbL file of every Segment (ADR-039 §10, §12): public, no session (the database is offered
 * to anyone, free of charge, ODbL §4.6). Redirects to the bucket rather than streaming it.
 */
@Controller("open-data")
export class OpenDataController {
  constructor(private readonly segments: SegmentsService) {}

  @Get("segments.ndjson.gz")
  @Redirect()
  @Header("Cache-Control", CACHE_CONTROL)
  @ApiResponse({
    status: HttpStatus.FOUND,
    description: "Vers le fichier NDJSON gzippé (en-tête de licence ODbL, puis une Feature GeoJSON par Segment)",
  })
  @ApiResponse({ status: HttpStatus.NOT_FOUND, description: "`open_data_not_ready` avant le premier export" })
  async segmentsFile(): Promise<{ url: string; statusCode: number }> {
    const signed = await this.segments.openDataUrl(SIGNED_URL_TTL_S);
    if (!signed) {
      throw new NotFoundException({
        code: "open_data_not_ready",
        message: "The open data file is written by the weekly export",
      });
    }
    return { url: signed.url, statusCode: HttpStatus.FOUND };
  }
}
