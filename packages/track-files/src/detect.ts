import type { TrackFileFormat } from "./types.js";

const XML_PROLOG_WINDOW = 4096;
const ROOT_RE = /^<(?:[A-Za-z_][\w.-]*:)?(gpx|TrainingCenterDatabase)(?=[\s>/])/;

/** Skips whitespace, <?xml?>, comments and DOCTYPE before the root element. */
function skipProlog(text: string): string {
  let s = text.replace(/^﻿/, "");
  for (;;) {
    s = s.trimStart();
    const m = /^(?:<\?[\s\S]*?\?>|<!--[\s\S]*?-->|<!DOCTYPE[^>[]*(?:\[[\s\S]*?\])?\s*>)/i.exec(s);
    if (!m) return s;
    s = s.slice(m[0].length);
  }
}

function isFit(bytes: Uint8Array): boolean {
  return (
    bytes.length >= 12 &&
    bytes[8] === 0x2e &&
    bytes[9] === 0x46 &&
    bytes[10] === 0x49 &&
    bytes[11] === 0x54
  );
}

/** Sniffs the format from content only (ADR-028 §5, "Format sniffing"). */
export function detectTrackFileFormat(bytes: Uint8Array): TrackFileFormat | undefined {
  if (isFit(bytes)) return "fit";
  const head = new TextDecoder("utf-8").decode(bytes.subarray(0, XML_PROLOG_WINDOW));
  const m = ROOT_RE.exec(skipProlog(head));
  if (!m) return undefined;
  return m[1] === "gpx" ? "gpx" : "tcx";
}
