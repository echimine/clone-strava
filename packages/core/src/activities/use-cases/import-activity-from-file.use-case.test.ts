import { gunzipSync } from "node:zlib";
import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  ACTIVITY_IMPORT_COMPLETED_EVENT,
  ACTIVITY_IMPORT_FAILED_EVENT,
  activityTraceKey,
} from "@repo/contracts";
import { PermanentProcessingError } from "../domain/processing-error.js";
import type { ActivityImportRow } from "../repositories/activity-import.repository.js";
import { ImportActivityFromFileUseCase } from "./import-activity-from-file.use-case.js";

const USER = "11111111-1111-4111-8111-111111111111";
const IMPORT_ID = "22222222-2222-4222-8222-222222222222";
const OTHER_ACTIVITY = "33333333-3333-4333-8333-333333333333";

function gpx(points: Array<{ lat: number; lon: number; time?: string }>, type = "running"): Uint8Array {
  const trkpts = points
    .map((p) => `<trkpt lat="${p.lat}" lon="${p.lon}">${p.time ? `<time>${p.time}</time>` : ""}</trkpt>`)
    .join("");
  return new TextEncoder().encode(
    `<?xml version="1.0"?><gpx version="1.1" creator="test" xmlns="http://www.topografix.com/GPX/1/1">` +
      `<trk><name>Tour du lac</name><type>${type}</type><trkseg>${trkpts}</trkseg></trk></gpx>`,
  );
}

// 10 minutes of running, one point per minute, ~111 m apart.
const RUN = gpx(
  Array.from({ length: 11 }, (_, i) => ({
    lat: 48 + i * 0.001,
    lon: 2,
    time: new Date(Date.UTC(2026, 5, 1, 6, i)).toISOString(),
  })),
);

function importRow(overrides: Partial<ActivityImportRow> = {}): ActivityImportRow {
  return {
    id: IMPORT_ID,
    userId: USER,
    format: "gpx",
    originalFileName: "lac.gpx",
    sizeBytes: RUN.byteLength,
    sha256: null,
    status: "processing",
    activityId: null,
    requestedSportTypeCode: null,
    requestedTitle: null,
    requestedVisibility: null,
    error: null,
    attempts: 0,
    createdAt: new Date(),
    processedAt: null,
    ...overrides,
  };
}

function setup(options: { file?: Uint8Array; row?: Partial<ActivityImportRow> } = {}) {
  const row = importRow(options.row);
  const imports = {
    findById: vi.fn().mockResolvedValue(row),
    incrementAttempts: vi.fn(),
    findImportedBySha256: vi.fn().mockResolvedValue(undefined),
    markImported: vi.fn(),
    markDuplicate: vi.fn(),
    markFailed: vi.fn(),
  };
  const activities = {
    findOverlapping: vi.fn().mockResolvedValue([]),
    insertIfAbsent: vi.fn(),
  };
  const sports = {
    findByCode: vi.fn(async (code: string) =>
      ["run", "ride"].includes(code) ? { code, isActive: true, minDurationS: 60 } : undefined,
    ),
  };
  const users = {
    getActivityDefaults: vi.fn().mockResolvedValue({ defaultVisibility: "followers", privacyZoneRadiusM: 200 }),
  };
  const storage = {
    getObject: vi.fn().mockResolvedValue(options.file ?? RUN),
    putObject: vi.fn(),
  };
  const analytics = { capture: vi.fn() };
  const events = { emit: vi.fn() };
  const db = { transaction: vi.fn(async (fn: (tx: unknown) => Promise<void>) => fn("tx")) };

  const useCase = new ImportActivityFromFileUseCase(
    db as never,
    imports as never,
    activities as never,
    sports as never,
    users as never,
    storage as never,
    analytics as never,
    events as never,
  );
  return { useCase, imports, activities, storage, events, analytics };
}

const job = { importId: IMPORT_ID, userId: USER, requestId: "req_1" };

describe("ImportActivityFromFileUseCase", () => {
  let ctx: ReturnType<typeof setup>;

  beforeEach(() => {
    ctx = setup();
  });

  it("creates the activity with the import id, writes the trace and emits completed", async () => {
    await expect(ctx.useCase.execute(job)).resolves.toEqual({ outcome: "imported", activityId: IMPORT_ID });

    const [values, tx] = ctx.activities.insertIfAbsent.mock.calls[0]!;
    expect(tx).toBe("tx");
    expect(values).toMatchObject({
      id: IMPORT_ID,
      userId: USER,
      sportTypeCode: "run",
      title: "Tour du lac",
      visibility: "followers",
      processingStatus: "processing",
      source: "imported",
    });
    expect(ctx.imports.markImported).toHaveBeenCalledWith(
      IMPORT_ID,
      { activityId: IMPORT_ID, sha256: expect.stringMatching(/^[0-9a-f]{64}$/) },
      "tx",
    );

    const [key, body] = ctx.storage.putObject.mock.calls[0]!;
    expect(key).toBe(activityTraceKey(USER, IMPORT_ID));
    const trace = JSON.parse(gunzipSync(body as Uint8Array).toString("utf8"));
    expect(trace.schemaVersion).toBe(1);
    expect(trace.points).toHaveLength(11);

    expect(ctx.events.emit).toHaveBeenCalledWith(ACTIVITY_IMPORT_COMPLETED_EVENT, {
      importId: IMPORT_ID,
      activityId: IMPORT_ID,
      userId: USER,
      outcome: "imported",
      requestId: "req_1",
    });
  });

  it("prefers the overrides sent by the app", async () => {
    ctx = setup({ row: { requestedSportTypeCode: "ride", requestedTitle: "Vélotaf", requestedVisibility: "private" } });
    await ctx.useCase.execute(job);
    expect(ctx.activities.insertIfAbsent.mock.calls[0]![0]).toMatchObject({
      sportTypeCode: "ride",
      title: "Vélotaf",
      visibility: "private",
    });
  });

  it("marks an identical file as duplicate without parsing it", async () => {
    ctx.imports.findImportedBySha256.mockResolvedValue({ activityId: OTHER_ACTIVITY });
    await expect(ctx.useCase.execute(job)).resolves.toEqual({ outcome: "duplicate", activityId: OTHER_ACTIVITY });
    expect(ctx.imports.markDuplicate).toHaveBeenCalled();
    expect(ctx.activities.insertIfAbsent).not.toHaveBeenCalled();
    expect(ctx.events.emit).toHaveBeenCalledWith(
      ACTIVITY_IMPORT_COMPLETED_EVENT,
      expect.objectContaining({ outcome: "duplicate", activityId: OTHER_ACTIVITY }),
    );
  });

  it("marks the same workout from another device as duplicate", async () => {
    ctx.activities.findOverlapping.mockResolvedValue([
      {
        id: OTHER_ACTIVITY,
        startedAt: new Date(Date.UTC(2026, 5, 1, 6, 1)),
        endedAt: new Date(Date.UTC(2026, 5, 1, 6, 12)),
      },
    ]);
    await expect(ctx.useCase.execute(job)).resolves.toMatchObject({ outcome: "duplicate" });
  });

  it("does not treat a small overlap as a duplicate", async () => {
    ctx.activities.findOverlapping.mockResolvedValue([
      {
        id: OTHER_ACTIVITY,
        startedAt: new Date(Date.UTC(2026, 5, 1, 6, 8)),
        endedAt: new Date(Date.UTC(2026, 5, 1, 7, 0)),
      },
    ]);
    await expect(ctx.useCase.execute(job)).resolves.toMatchObject({ outcome: "imported" });
  });

  it.each([
    ["a corrupt file", new TextEncoder().encode("<gpx><trk>"), "invalid_file"],
    ["a file without times", gpx([{ lat: 1, lon: 1 }, { lat: 2, lon: 2 }]), "no_timestamps"],
    ["an unknown sport", gpx([{ lat: 1, lon: 1, time: "2026-06-01T06:00:00Z" }, { lat: 1.01, lon: 1, time: "2026-06-01T06:10:00Z" }], "other"), "unknown_sport"],
    ["a too short activity", gpx([{ lat: 1, lon: 1, time: "2026-06-01T06:00:00Z" }, { lat: 1.0001, lon: 1, time: "2026-06-01T06:00:30Z" }]), "invalid_duration"],
  ])("fails permanently on %s", async (_label, file, code) => {
    ctx = setup({ file });
    await expect(ctx.useCase.execute(job)).rejects.toBeInstanceOf(PermanentProcessingError);
    expect(ctx.imports.markFailed.mock.calls[0]![1]).toBe(code);
    expect(ctx.events.emit).toHaveBeenCalledWith(
      ACTIVITY_IMPORT_FAILED_EVENT,
      expect.objectContaining({ importId: IMPORT_ID, code }),
    );
    expect(ctx.activities.insertIfAbsent).not.toHaveBeenCalled();
  });

  it("is a no-op for an import that is no longer processing (replayed job)", async () => {
    ctx = setup({ row: { status: "imported" } });
    await expect(ctx.useCase.execute(job)).resolves.toEqual({ outcome: "skipped" });
    expect(ctx.storage.getObject).not.toHaveBeenCalled();
  });

  it("lets technical errors through for a retry", async () => {
    ctx.storage.getObject.mockRejectedValue(new Error("bucket down"));
    await expect(ctx.useCase.execute(job)).rejects.toThrow("bucket down");
    expect(ctx.imports.markFailed).not.toHaveBeenCalled();
  });

  it("turns a lost race on the unique index into a duplicate", async () => {
    ctx.imports.markImported.mockRejectedValue(Object.assign(new Error("dup"), { cause: { code: "23505" } }));
    ctx.imports.findImportedBySha256
      .mockResolvedValueOnce(undefined)
      .mockResolvedValueOnce({ activityId: OTHER_ACTIVITY });
    await expect(ctx.useCase.execute(job)).resolves.toEqual({ outcome: "duplicate", activityId: OTHER_ACTIVITY });
  });
});
