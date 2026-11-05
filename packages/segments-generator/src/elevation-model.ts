import { closeSync, openSync, readFileSync, readSync } from "node:fs";
import type { ElevationAt } from "./climbs.js";

/** Rows kept in memory per raster: a country-wide row is a few hundred kilobytes. */
const ROW_CACHE_SIZE = 512;

interface EhdrHeader {
  rows: number;
  cols: number;
  /** Center of the upper-left cell, degrees. */
  ulLon: number;
  ulLat: number;
  cellLon: number;
  cellLat: number;
  littleEndian: boolean;
  noData: number | null;
}

/**
 * An elevation raster in WGS 84, as `gdalwarp -t_srs EPSG:4326 -of EHdr -ot Float32` writes it:
 * a `.hdr` header next to a `.bil` of float32 cells. Read by rows on demand, bilinear between cell
 * centers; `null` outside the raster or next to a void.
 */
export class EhdrRaster {
  private readonly header: EhdrHeader;
  private readonly fd: number;
  private readonly rows = new Map<number, Float32Array>();

  constructor(hdrPath: string) {
    this.header = parseHeader(readFileSync(hdrPath, "utf8"));
    this.fd = openSync(hdrPath.replace(/\.hdr$/i, ".bil"), "r");
  }

  readonly elevationAt: ElevationAt = (lon, lat) => {
    const { ulLon, ulLat, cellLon, cellLat, rows, cols } = this.header;
    const col = (lon - ulLon) / cellLon;
    const row = (ulLat - lat) / cellLat;
    if (col < 0 || row < 0 || col > cols - 1 || row > rows - 1) {
      return null;
    }
    const c0 = Math.min(Math.floor(col), cols - 2);
    const r0 = Math.min(Math.floor(row), rows - 2);
    const fc = col - c0;
    const fr = row - r0;
    const corners = [this.cell(r0, c0), this.cell(r0, c0 + 1), this.cell(r0 + 1, c0), this.cell(r0 + 1, c0 + 1)];
    if (corners.some((value) => value === null)) {
      return null;
    }
    const [a, b, c, d] = corners as number[];
    return (a! * (1 - fc) + b! * fc) * (1 - fr) + (c! * (1 - fc) + d! * fc) * fr;
  };

  close(): void {
    closeSync(this.fd);
  }

  private cell(row: number, col: number): number | null {
    const value = this.row(row)[col]!;
    const { noData } = this.header;
    return Number.isNaN(value) || (noData !== null && Math.abs(value - noData) < 1e-3) ? null : value;
  }

  private row(index: number): Float32Array {
    const cached = this.rows.get(index);
    if (cached) {
      return cached;
    }
    const { cols, littleEndian } = this.header;
    const buffer = Buffer.alloc(cols * 4);
    readSync(this.fd, buffer, 0, buffer.length, index * cols * 4);
    const row = new Float32Array(cols);
    for (let i = 0; i < cols; i++) {
      row[i] = littleEndian ? buffer.readFloatLE(i * 4) : buffer.readFloatBE(i * 4);
    }
    if (this.rows.size >= ROW_CACHE_SIZE) {
      this.rows.delete(this.rows.keys().next().value!);
    }
    this.rows.set(index, row);
    return row;
  }
}

function parseHeader(text: string): EhdrHeader {
  const values = new Map(
    text
      .split(/\r?\n/)
      .map((line) => line.trim().split(/\s+/))
      .filter((parts) => parts.length >= 2)
      .map(([key, value]) => [key!.toUpperCase(), value!]),
  );
  const number = (key: string) => {
    const value = Number(values.get(key));
    if (!Number.isFinite(value)) {
      throw new Error(`EHdr header: missing ${key}`);
    }
    return value;
  };
  if ((values.get("NBITS") ?? "32") !== "32" || (values.get("PIXELTYPE") ?? "FLOAT").toUpperCase() !== "FLOAT") {
    throw new Error("EHdr header: only float32 rasters are read (gdalwarp -ot Float32)");
  }
  if (Number(values.get("NBANDS") ?? "1") !== 1) {
    throw new Error("EHdr header: one band expected");
  }
  return {
    rows: number("NROWS"),
    cols: number("NCOLS"),
    ulLon: number("ULXMAP"),
    ulLat: number("ULYMAP"),
    cellLon: number("XDIM"),
    cellLat: number("YDIM"),
    littleEndian: (values.get("BYTEORDER") ?? "I").toUpperCase() === "I",
    noData: values.has("NODATA") ? number("NODATA") : null,
  };
}

/**
 * Elevation models in order of preference (ADR-039 §10: IGN RGE ALTI in France, Copernicus
 * GLO-30 elsewhere, SRTM as fallback): the first one with a value wins.
 */
export function firstAvailable(models: ElevationAt[]): ElevationAt {
  return (lon, lat) => {
    for (const model of models) {
      const value = model(lon, lat);
      if (value !== null) {
        return value;
      }
    }
    return null;
  };
}
