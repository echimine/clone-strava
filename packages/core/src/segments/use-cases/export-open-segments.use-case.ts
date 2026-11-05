import { Injectable, Logger } from "@nestjs/common";
import { createGzip } from "node:zlib";
import {
  OPEN_DATA_SEGMENTS_KEY,
  type OpenDataSegmentFeature,
  type OpenDataSegmentsHeader,
} from "@repo/contracts";
import { StorageService } from "../../storage/index.js";
import { SegmentRepository } from "../repositories/segment.repository.js";

/** Segments read per query. */
const PAGE_SIZE = 1000;

/**
 * The notices the file travels with (ODbL §4.3, §4.6; Copernicus licence art. 6(b), 6(c)).
 */
export const OPEN_DATA_ATTRIBUTION = [
  "© les contributeurs d'OpenStreetMap, https://www.openstreetmap.org/copyright, sous ODbL 1.0",
  "produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved",
  "The organisations in charge of the Copernicus programme by law or by delegation do not incur any liability for any use of the Copernicus WorldDEM-30",
  "IGN RGE ALTI, Licence Ouverte Etalab 2.0",
] as const;

/**
 * `export-segments-odbl` (ADR-039 §10, §13): every Segment, the athletes' included, as gzipped
 * NDJSON (a licence header line, then one GeoJSON Feature per Segment) under
 * {@link OPEN_DATA_SEGMENTS_KEY}. Name, sport, path, figures; no creator, no provenance, no
 * Effort. Streamed page by page, so the whole base never sits in memory uncompressed.
 */
@Injectable()
export class ExportOpenSegmentsUseCase {
  private readonly logger = new Logger(ExportOpenSegmentsUseCase.name);

  constructor(
    private readonly segments: SegmentRepository,
    private readonly storage: StorageService,
  ) {}

  async execute(): Promise<{ segmentCount: number }> {
    const gzip = createGzip();
    const chunks: Buffer[] = [];
    gzip.on("data", (chunk: Buffer) => chunks.push(chunk));
    const finished = new Promise<void>((resolve, reject) => {
      gzip.on("end", resolve);
      gzip.on("error", reject);
    });
    const write = (record: OpenDataSegmentsHeader | OpenDataSegmentFeature) => gzip.write(`${JSON.stringify(record)}\n`);

    write({
      type: "Metadata",
      license: "ODbL-1.0",
      licenseUrl: "https://opendatacommons.org/licenses/odbl/1-0/",
      attribution: [...OPEN_DATA_ATTRIBUTION],
      generatedAt: new Date().toISOString(),
    });
    let segmentCount = 0;
    let afterId: string | null = null;
    for (;;) {
      const page = await this.segments.pageForOpenData(afterId, PAGE_SIZE);
      if (page.length === 0) {
        break;
      }
      for (const segment of page) {
        write({
          type: "Feature",
          id: segment.id,
          geometry: { type: "LineString", coordinates: segment.coordinates },
          properties: {
            name: segment.name,
            sport: segment.sport,
            distanceM: segment.distanceM,
            elevationGainM: segment.elevationGainM,
            avgGrade: segment.avgGrade,
            maxGrade: segment.maxGrade,
            climbCategory: segment.climbCategory,
          },
        });
      }
      segmentCount += page.length;
      afterId = page.at(-1)!.id;
    }
    gzip.end();
    await finished;

    await this.storage.putObject(OPEN_DATA_SEGMENTS_KEY, Buffer.concat(chunks), { contentType: "application/gzip" });
    this.logger.log(`ODbL export: ${segmentCount} segment(s) written to ${OPEN_DATA_SEGMENTS_KEY}`);
    return { segmentCount };
  }
}
