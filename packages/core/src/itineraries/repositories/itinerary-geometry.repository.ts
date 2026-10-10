import { Inject, Injectable } from "@nestjs/common";
import { asc, eq, sql } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import type { LonLat } from "@repo/geo";
import { DATABASE, type DbExecutor } from "../../infrastructure/index.js";
import type { AssembledLeg } from "../domain/assemble-itinerary-track.js";
import { parseGeoJsonLineString, parseGeoJsonPoint, toLineStringEwkt, toPointEwkt } from "./geometry-format.js";

const waypointTable = schema.itineraryWaypoint;
const legTable = schema.itineraryLeg;

/**
 * Reads and writes on `itineraries.itinerary_waypoint` and
 * `itineraries.itinerary_leg` (ADR-030 §5): an Itinerary's Waypoints and
 * Legs, always written together and replaced entirely.
 */
@Injectable()
export class ItineraryGeometryRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  /**
   * Replaces the Waypoints and Legs of an Itinerary (create and full
   * update). Run it in the transaction that writes the `itinerary` row.
   */
  async replace(
    itineraryId: string,
    geometry: { waypoints: LonLat[]; legs: AssembledLeg[] },
    executor: DbExecutor = this.db,
  ): Promise<void> {
    await executor.delete(waypointTable).where(eq(waypointTable.itineraryId, itineraryId));
    await executor.delete(legTable).where(eq(legTable.itineraryId, itineraryId));
    await executor.insert(waypointTable).values(
      geometry.waypoints.map((waypoint, position) => ({ itineraryId, position, location: toPointEwkt(waypoint) })),
    );
    await executor.insert(legTable).values(
      geometry.legs.map((leg, position) => ({ itineraryId, position, mode: leg.mode, path: toLineStringEwkt(leg.path) })),
    );
  }

  /** Waypoints and Legs of an Itinerary, in order. */
  async find(itineraryId: string): Promise<{ waypoints: LonLat[]; legs: AssembledLeg[] }> {
    const [waypoints, legs] = await Promise.all([
      this.db
        .select({ location: sql<string>`ST_AsGeoJSON(${waypointTable.location})` })
        .from(waypointTable)
        .where(eq(waypointTable.itineraryId, itineraryId))
        .orderBy(asc(waypointTable.position)),
      this.db
        .select({ mode: legTable.mode, path: sql<string>`ST_AsGeoJSON(${legTable.path})` })
        .from(legTable)
        .where(eq(legTable.itineraryId, itineraryId))
        .orderBy(asc(legTable.position)),
    ]);
    return {
      waypoints: waypoints.map(({ location }) => parseGeoJsonPoint(location)),
      legs: legs.map(({ mode, path }) => ({ mode, path: parseGeoJsonLineString(path) })),
    };
  }
}
