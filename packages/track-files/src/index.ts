import { detectTrackFileFormat } from "./detect.js";
import { parseFit } from "./fit.js";
import { parseGpx } from "./gpx.js";
import { parseTcx } from "./tcx.js";
import { TrackFileError, type ParseOptions, type ParsedTrackFile } from "./types.js";

export * from "./types.js";
export { detectTrackFileFormat } from "./detect.js";
export { parseGpx } from "./gpx.js";
export { parseTcx } from "./tcx.js";
export { parseFit } from "./fit.js";

/** Sniffs the content first; the declared format is only a fallback (ADR-028 §5). */
export function parseTrackFile(bytes: Uint8Array, options: ParseOptions = {}): ParsedTrackFile {
  const format = detectTrackFileFormat(bytes) ?? options.declaredFormat;
  switch (format) {
    case "gpx":
      return parseGpx(bytes, options);
    case "tcx":
      return parseTcx(bytes, options);
    case "fit":
      return parseFit(bytes, options);
    default:
      throw new TrackFileError("unsupported_format", "Unrecognized track file format");
  }
}
