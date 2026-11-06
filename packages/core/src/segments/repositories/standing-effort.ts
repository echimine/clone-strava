import { sql, type SQL, type SQLWrapper } from "drizzle-orm";
import { DEFAULT_PRIVACY_ZONE_RADIUS_M } from "../domain/segment-sports.js";

/**
 * The one SQL definition of an Effort that stands (ADR-039 §8), shared by every read: the
 * Leaderboard, the sheet, « Résultats » and the Map. The athlete's radius is read now from the
 * published view `users.leaderboard_athlete`, left joined: without a row, the default radius.
 */

const E = sql.raw("e");
const A = sql.raw("a");
const P = sql.raw("p");

/**
 * Outside its athlete's current privacy zone (ADR-039 §6): both crow-fly distances to the
 * Activity's ends at least the radius. `effort` is the `segment_effort` row, `athlete` the left
 * joined `users.leaderboard_athlete` row (a table, a view or a raw alias).
 */
export function outsidePrivacyZone(effort: SQLWrapper, athlete: SQLWrapper): SQL {
  const radius = sql`coalesce(${athlete}.privacy_zone_radius_m, ${sql.raw(String(DEFAULT_PRIVACY_ZONE_RADIUS_M))})`;
  return sql`${effort}.min_distance_to_activity_start_m >= ${radius}
    and ${effort}.min_distance_to_activity_end_m >= ${radius}`;
}

/**
 * Stands on the Leaderboard: of a public Activity (`activity`, a joined row of the published view
 * `activities.leaderboard_activity`, processed Activities only), not rejected, outside the
 * privacy zone. A suspicious Effort stands.
 */
export function standsOnLeaderboard(effort: SQLWrapper, activity: SQLWrapper, athlete: SQLWrapper): SQL {
  return sql`${activity}.visibility = 'public' and ${effort}.status <> 'rejected'
    and ${outsidePrivacyZone(effort, athlete)}`;
}

/**
 * `from … where` of the Efforts that stand, as `e` (Effort), `a` (its Activity) and `p` (its
 * athlete, maybe null); append `and …` conditions.
 */
export const STANDING_EFFORTS = sql`
  from segments.segment_effort e
  join activities.leaderboard_activity a on a.id = e.activity_id
  left join users.leaderboard_athlete p on p.user_id = e.user_id
  where ${standsOnLeaderboard(E, A, P)}`;
