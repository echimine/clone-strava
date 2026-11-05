import { InjectQueue } from "@nestjs/bullmq";
import { Injectable, Logger } from "@nestjs/common";
import type { Queue } from "bullmq";
import {
  MATCH_SEGMENTS_JOB_NAME,
  SEGMENT_JOB_PRIORITY,
  SEGMENTS_QUEUE_NAME,
  matchSegmentsImportJobId,
  nervoSegmentLineSchema,
  type MatchSegmentsJob,
  type NervoSegmentLine,
} from "@repo/contracts";
import { encodeWithinBudget } from "@repo/geo";
import { DEFAULT_JOB_RETRY } from "../../infrastructure/index.js";
import { isSameSegment, SEGMENT_MATCHING_THRESHOLDS } from "../domain/match-segment.js";
import { marginInDegrees, SEGMENT_SPORTS } from "../domain/segment-sports.js";
import { ActivityMatchingRepository } from "../repositories/activity-matching.repository.js";
import { ExcludedSourceKeyRepository } from "../repositories/excluded-source-key.repository.js";
import { SegmentRepository } from "../repositories/segment.repository.js";

/** What `pnpm segments:import` prints (ADR-039 §10). */
export interface NervoImportReport {
  /** Suffix of this run's `match-segments` job ids. */
  importId: string;
  inserted: number;
  /** Source key already loaded: runs only add, never modify. */
  alreadyPresent: number;
  /** Source key an Administrator deleted. */
  excluded: number;
  /** Same path as an existing Segment of the same sport, both ways: the existing one stays. */
  duplicates: number;
  /** 1-based line numbers the generator's schema refuses. */
  invalid: Array<{ line: number; reason: string }>;
  activitiesEnqueued: number;
}

/** Lines whose source keys are looked up together. */
const CHUNK_SIZE = 500;
/** Activities enqueued per `addBulk`. */
const ENQUEUE_PAGE_SIZE = 1000;
/** Same budget as an Itinerary's thumbnail (ADR-030 §5). */
const MAP_POLYLINE = { maxChars: 2000, firstToleranceM: 5 };

/**
 * `pnpm segments:import <file>` (ADR-039 §7, §10): loads the generator's NDJSON, idempotent on
 * `source_key`, skipping excluded keys and duplicates of an existing Segment of the same sport;
 * never modifies a Segment. Then, rather than a retro-matching per Segment, replays
 * `match-segments` at low priority once per processed Activity of the sports with a map, so each
 * trace is read once.
 */
@Injectable()
export class ImportNervoSegmentsUseCase {
  private readonly logger = new Logger(ImportNervoSegmentsUseCase.name);

  constructor(
    private readonly segments: SegmentRepository,
    private readonly excludedKeys: ExcludedSourceKeyRepository,
    private readonly matchings: ActivityMatchingRepository,
    @InjectQueue(SEGMENTS_QUEUE_NAME) private readonly queue: Queue<MatchSegmentsJob>,
  ) {}

  async execute(lines: AsyncIterable<string> | Iterable<string>): Promise<NervoImportReport> {
    const report: NervoImportReport = {
      importId: new Date().toISOString().replace(/[-:.]/g, ""),
      inserted: 0,
      alreadyPresent: 0,
      excluded: 0,
      duplicates: 0,
      invalid: [],
      activitiesEnqueued: 0,
    };
    let chunk: NervoSegmentLine[] = [];
    let lineNumber = 0;
    for await (const text of lines) {
      lineNumber++;
      if (text.trim() === "") {
        continue;
      }
      const parsed = parseLine(text);
      if ("reason" in parsed) {
        report.invalid.push({ line: lineNumber, reason: parsed.reason });
        continue;
      }
      chunk.push(parsed.line);
      if (chunk.length >= CHUNK_SIZE) {
        await this.load(chunk, report);
        chunk = [];
      }
    }
    await this.load(chunk, report);
    if (report.inserted > 0) {
      report.activitiesEnqueued = await this.replayMatching(report.importId);
    }
    return report;
  }

  private async load(chunk: NervoSegmentLine[], report: NervoImportReport): Promise<void> {
    const keys = chunk.map((line) => line.sourceKey);
    const [existing, excluded] = await Promise.all([
      this.segments.existingSourceKeys(keys),
      this.excludedKeys.excludedAmong(keys),
    ]);
    for (const line of chunk) {
      if (excluded.has(line.sourceKey)) {
        report.excluded++;
      } else if (existing.has(line.sourceKey)) {
        report.alreadyPresent++;
      } else if (await this.duplicatesAnExisting(line)) {
        report.duplicates++;
      } else if (await this.insert(line)) {
        report.inserted++;
        existing.add(line.sourceKey);
      } else {
        report.alreadyPresent++;
      }
    }
  }

  /** ADR-039 §10: `matchSegment` both ways against the Segments of the sport near its ends. */
  private async duplicatesAnExisting(line: NervoSegmentLine): Promise<boolean> {
    const path = line.path.map(([lon, lat]) => ({ lon, lat }));
    const ewkt = `SRID=4326;LINESTRING(${line.path.map(([lon, lat]) => `${lon} ${lat}`).join(",")})`;
    const marginDeg = marginInDegrees(
      2 * SEGMENT_MATCHING_THRESHOLDS.lineHalfWidthM,
      path.map((point) => point.lat),
    );
    const candidates = await this.segments.findNearTrace(line.sport, ewkt, marginDeg);
    return candidates.some((candidate) => isSameSegment(path, candidate.path));
  }

  private insert(line: NervoSegmentLine): Promise<boolean> {
    return this.segments.insertNervo({
      sourceKey: line.sourceKey,
      sportTypeCode: line.sport,
      name: line.name,
      path: line.path,
      distanceM: line.distanceM,
      avgGrade: line.avgGrade,
      maxGrade: line.maxGrade,
      elevationGainM: line.elevationGainM,
      minAltitudeM: line.minAltitudeM,
      maxAltitudeM: line.maxAltitudeM,
      climbCategory: line.climbCategory,
      mapPolyline: encodeWithinBudget(
        line.path.map(([lon, lat]) => ({ lon, lat })),
        MAP_POLYLINE,
      ),
    });
  }

  /** ADR-039 §7: one low-priority `match-segments` per processed Activity of the map sports. */
  private async replayMatching(importId: string): Promise<number> {
    let enqueued = 0;
    let afterId: string | null = null;
    for (;;) {
      const page = await this.matchings.pageProcessed(SEGMENT_SPORTS, afterId, ENQUEUE_PAGE_SIZE);
      if (page.length === 0) {
        break;
      }
      await this.queue.addBulk(
        page.map(({ activityId, userId }) => ({
          name: MATCH_SEGMENTS_JOB_NAME,
          data: { activityId, userId },
          opts: {
            ...DEFAULT_JOB_RETRY,
            priority: SEGMENT_JOB_PRIORITY.backgroundMatching,
            jobId: matchSegmentsImportJobId(activityId, importId),
          },
        })),
      );
      enqueued += page.length;
      afterId = page.at(-1)!.activityId;
    }
    this.logger.log(`Nervo import ${importId}: ${enqueued} activity(ies) enqueued for matching`);
    return enqueued;
  }
}

function parseLine(text: string): { line: NervoSegmentLine } | { reason: string } {
  let json: unknown;
  try {
    json = JSON.parse(text);
  } catch {
    return { reason: "not JSON" };
  }
  const parsed = nervoSegmentLineSchema.safeParse(json);
  return parsed.success
    ? { line: parsed.data }
    : { reason: parsed.error.issues.map((issue) => `${issue.path.join(".")}: ${issue.message}`).join("; ") };
}
