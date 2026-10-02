import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { detectTrackFileFormat, parseGpx, parseTrackFile, TrackFileError } from "./index.js";

const fixture = (name: string): Uint8Array =>
  new Uint8Array(readFileSync(join(__dirname, "..", "fixtures", name)));
const enc = (s: string): Uint8Array => new TextEncoder().encode(s);
const code = (fn: () => unknown): string | undefined => {
  try {
    fn();
  } catch (e) {
    return e instanceof TrackFileError ? e.code : "other";
  }
  return undefined;
};

describe("detectTrackFileFormat", () => {
  it("detects the three fixtures", () => {
    expect(detectTrackFileFormat(fixture("ride.gpx"))).toBe("gpx");
    expect(detectTrackFileFormat(fixture("ride.tcx"))).toBe("tcx");
    expect(detectTrackFileFormat(fixture("ride.fit"))).toBe("fit");
  });

  it("skips BOM, whitespace, declaration and comments", () => {
    const xml = `﻿  \n<?xml version="1.0"?>\n<!-- c -->\n<gpx></gpx>`;
    expect(detectTrackFileFormat(enc(xml))).toBe("gpx");
  });

  it("accepts namespace-prefixed roots", () => {
    expect(detectTrackFileFormat(enc(`<g:gpx xmlns:g="x"/>`))).toBe("gpx");
    expect(detectTrackFileFormat(enc(`<t:TrainingCenterDatabase xmlns:t="x"></t:TrainingCenterDatabase>`))).toBe("tcx");
  });

  it("returns undefined for garbage and unrelated XML", () => {
    expect(detectTrackFileFormat(enc("hello"))).toBeUndefined();
    expect(detectTrackFileFormat(enc("<kml></kml>"))).toBeUndefined();
    expect(detectTrackFileFormat(enc("<gpxish/>"))).toBeUndefined();
    expect(detectTrackFileFormat(new Uint8Array(0))).toBeUndefined();
  });
});

describe("parseTrackFile", () => {
  it("content wins over the declared format", () => {
    const r = parseTrackFile(fixture("ride.gpx"), { declaredFormat: "fit" });
    expect(r.format).toBe("gpx");
  });

  it("falls back to the declared format, then fails as unsupported", () => {
    expect(code(() => parseTrackFile(enc("nope"), { declaredFormat: "gpx" }))).toBe("invalid_file");
    expect(code(() => parseTrackFile(enc("nope")))).toBe("unsupported_format");
  });
});

describe("hardening and limits", () => {
  it("rejects malformed XML", () => {
    expect(code(() => parseGpx(enc(`<gpx><trk><trkseg></gpx>`)))).toBe("invalid_file");
  });

  it("rejects DOCTYPE with ENTITY declarations", () => {
    const xml = `<?xml version="1.0"?><!DOCTYPE gpx [<!ENTITY a "aaaa"><!ENTITY b "&a;&a;">]><gpx><trk><name>&b;</name></trk></gpx>`;
    expect(code(() => parseTrackFile(enc(xml)))).toBe("invalid_file");
  });

  it("rejects excessively deep XML", () => {
    const xml = `<gpx>${"<a>".repeat(100)}${"</a>".repeat(100)}</gpx>`;
    expect(code(() => parseGpx(enc(xml)))).toBe("invalid_file");
  });

  it("enforces maxPoints on every format", () => {
    expect(code(() => parseTrackFile(fixture("ride.gpx"), { maxPoints: 2 }))).toBe("too_many_points");
    expect(code(() => parseTrackFile(fixture("ride.tcx"), { maxPoints: 3 }))).toBe("too_many_points");
    expect(code(() => parseTrackFile(fixture("ride.fit"), { maxPoints: 5 }))).toBe("too_many_points");
    expect(parseTrackFile(fixture("ride.gpx"), { maxPoints: 3 }).points).toHaveLength(3);
  });
});
