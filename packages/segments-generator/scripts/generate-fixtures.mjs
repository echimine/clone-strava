// Writes the small, versioned fixtures of the generator's CLI test (ADR-039 §10): an OSM extract
// as `osmium export -f geojsonseq --add-unique-id=type_id` writes it, and two elevation rasters as
// `gdalwarp -of EHdr -ot Float32` writes them (a "national" one with a void east of the pass, and
// a coarser fallback). Synthetic data, nothing downloaded. Run: `pnpm --filter
// @repo/segments-generator fixtures`.
import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const out = join(dirname(fileURLToPath(import.meta.url)), "..", "fixtures");
const ORIGIN = { lon: 6, lat: 45 };
const M_PER_DEG_LAT = (6_371_000 * Math.PI) / 180;
const M_PER_DEG_LON = M_PER_DEG_LAT * Math.cos((ORIGIN.lat * Math.PI) / 180);
const lonLat = (x, y) => [
  Number((ORIGIN.lon + x / M_PER_DEG_LON).toFixed(7)),
  Number((ORIGIN.lat + y / M_PER_DEG_LAT).toFixed(7)),
];
const xy = (lon, lat) => ({ x: (lon - ORIGIN.lon) * M_PER_DEG_LON, y: (lat - ORIGIN.lat) * M_PER_DEG_LAT });

const ramp = (from, length, grade, base = 1000) => (t) => base + (grade / 100) * Math.min(Math.max(t - from, 0), length);
/** A pass at x = 4,000 m (4 km at 7 % each side), a summit path north, flat elsewhere. */
function altitude(x, y) {
  if (Math.abs(y) < 1500) {
    return x <= 4000 ? ramp(0, 4000, 7)(x) : ramp(0, 4000, 7)(8000 - x);
  }
  if (y > 4000 && y < 6000) {
    return ramp(0, 2000, 15, 1200)(x);
  }
  return 1000;
}

let id = 1;
const records = [];
const way = (tags, ...points) =>
  records.push({ type: "Feature", id: `w${id++}`, geometry: { type: "LineString", coordinates: points.map(([x, y]) => lonLat(x, y)) }, properties: tags });
const node = (tags, x, y) =>
  records.push({ type: "Feature", id: `n${id++}`, geometry: { type: "Point", coordinates: lonLat(x, y) }, properties: tags });

way({ highway: "secondary", ref: "D 900" }, [-500, 0], [2000, 0]);
way({ highway: "secondary", ref: "D 900" }, [2000, 0], [6000, 0]);
way({ highway: "secondary", ref: "D 900" }, [6000, 0], [8500, 0]);
way({ highway: "path", sac_scale: "mountain_hiking" }, [-200, 5000], [2000, 5000]);
way({ highway: "path", sac_scale: "alpine_hiking" }, [-200, 5400], [2000, 5400]);
way({ highway: "residential", name: "Route plate" }, [0, 3000], [3000, 3000]);
// An area is not a way to ride: `osmium` writes it as a polygon.
records.push({
  type: "Feature",
  id: "a1",
  geometry: { type: "Polygon", coordinates: [[lonLat(0, 0), lonLat(10, 0), lonLat(10, 10), lonLat(0, 0)]] },
  properties: { highway: "pedestrian", area: "yes" },
});
node({ mountain_pass: "yes", name: "Col du Test", ele: "1280" }, 4000, 0);
node({ natural: "peak", name: "Pic du Test", "name:fr": "Pic du Test" }, 2000, 5000);
node({ natural: "peak", name: "Aiguille du Test" }, 2000, 5400);
node({ place: "village", name: "Valtest" }, -300, 200);
node({ place: "village", name: "Autreville" }, 8300, -200);
node({ place: "hamlet", name: "Hameau du Bas" }, -300, 5100);
writeFileSync(join(out, "pilote.geojsonseq"), records.map((record) => `\x1e${JSON.stringify(record)}\n`).join(""));

/** A float32 EHdr raster over x -1,000..9,000 m, y -1,000..7,000 m. */
function raster(name, cellDeg, voidAt = () => false) {
  const [west, north] = lonLat(-1000, 7000);
  const [east, south] = lonLat(9000, -1000);
  const cols = Math.ceil((east - west) / cellDeg.lon) + 1;
  const rows = Math.ceil((north - south) / cellDeg.lat) + 1;
  const NODATA = -9999;
  const cells = Buffer.alloc(rows * cols * 4);
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      const { x, y } = xy(west + c * cellDeg.lon, north - r * cellDeg.lat);
      cells.writeFloatLE(voidAt(x, y) ? NODATA : altitude(x, y), (r * cols + c) * 4);
    }
  }
  writeFileSync(join(out, `${name}.bil`), cells);
  writeFileSync(
    join(out, `${name}.hdr`),
    [
      "BYTEORDER      I",
      "LAYOUT         BIL",
      `NROWS          ${rows}`,
      `NCOLS          ${cols}`,
      "NBANDS         1",
      "NBITS          32",
      "PIXELTYPE      FLOAT",
      `ULXMAP         ${west}`,
      `ULYMAP         ${north}`,
      `XDIM           ${cellDeg.lon}`,
      `YDIM           ${cellDeg.lat}`,
      `NODATA         ${NODATA}`,
      "",
    ].join("\n"),
  );
}

raster("mnt-national", { lon: 0.001, lat: 0.0008 }, (x) => x > 6000);
raster("mnt-secours", { lon: 0.002, lat: 0.0015 });
