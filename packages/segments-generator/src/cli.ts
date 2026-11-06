import { createWriteStream } from "node:fs";
import { resolve } from "node:path";
import { parseArgs } from "node:util";
import { NERVO_SEGMENT_SPORTS } from "@repo/contracts";
import { EhdrRaster, firstAvailable } from "./elevation-model.js";
import { generateSegments } from "./generate.js";
import { readOsmGeoJsonSeq } from "./osm.js";

export const HELP = `Générateur des Segments créés par Nervo (ADR-039 §10)

Hors ligne, pays par pays (pilote : la France), sur un poste ou une machine louée, jamais sur
le VPS. Écrit un fichier NDJSON, une ligne par Segment, que charge \`pnpm segments:import\`.

Usage
  pnpm segments:generate --osm <extrait.geojsonseq[.gz]> --dem <mnt.hdr> [--dem <secours.hdr> …] --out <segments.ndjson>

Options
  --osm    l'extrait OpenStreetMap, exporté par osmium en GeoJSON text sequence (voir 4.)
  --dem    un modèle d'élévation float32 en WGS 84, au format EHdr (.hdr à côté du .bil) ;
           répétable, dans l'ordre de préférence : IGN RGE ALTI, Copernicus GLO-30, SRTM
  --out    le fichier NDJSON écrit
  --help   cette aide

Préparer les entrées (France)
  1. L'extrait Geofabrik :
       curl -O https://download.geofabrik.de/europe/france-latest.osm.pbf
  2. Routes, chemins, cols, sommets et lieux :
       osmium tags-filter france-latest.osm.pbf w/highway n/mountain_pass=yes n/natural=peak \\
         n/place=city,town,village,hamlet,suburb,neighbourhood,quarter,locality -o fr-filtre.osm.pbf
  3. Une région à la fois si la mémoire manque (ici les Alpes) :
       osmium extract -b 5.4,44.0,7.8,46.5 fr-filtre.osm.pbf -o alpes.osm.pbf
  4. En GeoJSON text sequence, avec les identifiants OSM (la clé source en dépend) :
       osmium export alpes.osm.pbf -f geojsonseq --add-unique-id=type_id -o alpes.geojsonseq
  5. IGN RGE ALTI (Etalab 2.0 ; dalles ASC en Lambert-93), reprojeté en WGS 84 :
       gdalbuildvrt rgealti.vrt RGEALTI_*/**/*.asc
       gdalwarp -s_srs EPSG:2154 -t_srs EPSG:4326 -tr 0.0002 0.0002 -r bilinear -ot Float32 \\
         -of EHdr -te 5.4 44.0 7.8 46.5 rgealti.vrt rgealti-alpes.bil
  6. Copernicus GLO-30 (hors de France, ou pour combler l'IGN), tuiles COG publiques :
       aws s3 cp --no-sign-request \\
         s3://copernicus-dem-30m/Copernicus_DSM_COG_10_N45_00_E006_00_DEM/Copernicus_DSM_COG_10_N45_00_E006_00_DEM.tif .
       gdalbuildvrt cop30.vrt Copernicus_DSM_COG_10_*.tif
       gdalwarp -t_srs EPSG:4326 -ot Float32 -of EHdr -te 5.4 44.0 7.8 46.5 cop30.vrt cop30-alpes.bil
  7. SRTM GL1 (NASA Earthdata) en secours, de la même façon.
  Ni FABDEM, ni Open-Meteo, ni aucune donnée de Strava ou de Climbfinder.

Puis
  pnpm segments:generate --osm alpes.geojsonseq --dem rgealti-alpes.hdr --dem cop30-alpes.hdr --out segments-alpes.ndjson
  pnpm segments:import segments-alpes.ndjson     (contre la base cible, par un tunnel SSH)

Le fichier produit est une base dérivée d'OpenStreetMap, sous ODbL 1.0 (© les contributeurs
d'OpenStreetMap). Altitudes : « produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and
© Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and
ESA; all rights reserved », IGN RGE ALTI (Etalab 2.0).
`;

/** Paths as typed by the operator: `pnpm` runs the script elsewhere, `INIT_CWD` is where they were. */
const fromCaller = (path: string) => resolve(process.env.INIT_CWD ?? process.cwd(), path);

/** Exit code: 0 done, 2 bad usage. */
export async function runCli(argv: string[], log: (line: string) => void = console.log): Promise<number> {
  const { values } = parseArgs({
    args: argv,
    options: {
      osm: { type: "string" },
      dem: { type: "string", multiple: true },
      out: { type: "string" },
      help: { type: "boolean" },
    },
    strict: true,
  });
  if (values.help) {
    log(HELP);
    return 0;
  }
  if (!values.osm || !values.dem?.length || !values.out) {
    log("Il faut --osm, au moins un --dem et --out (voir --help).");
    return 2;
  }

  const osm = await readOsmGeoJsonSeq(fromCaller(values.osm));
  log(`OSM : ${osm.ways.length} ways, ${osm.nodes.length} nœuds`);
  const rasters = values.dem.map((path) => new EhdrRaster(fromCaller(path)));
  try {
    const segments = generateSegments(osm, firstAvailable(rasters.map((raster) => raster.elevationAt)));
    const out = createWriteStream(fromCaller(values.out));
    for (const segment of segments) {
      out.write(`${JSON.stringify(segment)}\n`);
    }
    await new Promise<void>((done, fail) => out.end((error?: Error | null) => (error ? fail(error) : done())));
    const perSport = NERVO_SEGMENT_SPORTS.map(
      (sport) => `${sport} ${segments.filter((segment) => segment.sport === sport).length}`,
    ).join(", ");
    log(`${segments.length} Segments (${perSport}) écrits dans ${values.out}`);
    return 0;
  } finally {
    rasters.forEach((raster) => raster.close());
  }
}

if (require.main === module) {
  runCli(process.argv.slice(2)).then(
    (code) => process.exit(code),
    (error: unknown) => {
      console.error("La génération a échoué", error);
      process.exit(1);
    },
  );
}
