import type { PaceUnit } from "@repo/contracts";

/** Public representation of a `sport_type` row (ADR-017), reference data. */
export interface SportType {
  code: string;
  category: string;
  iconName: string;
  tracksDistance: boolean;
  tracksElevation: boolean;
  usesGps: boolean;
  paceUnit: PaceUnit;
  minDurationS: number;
  minDistanceM: number;
  isActive: boolean;
}

/** `sport_type` row -> public representation (ADR-021 §2 rule 5). */
export function toSportType(row: SportType & Record<string, unknown>): SportType {
  return {
    code: row.code,
    category: row.category,
    iconName: row.iconName,
    tracksDistance: row.tracksDistance,
    tracksElevation: row.tracksElevation,
    usesGps: row.usesGps,
    paceUnit: row.paceUnit,
    minDurationS: row.minDurationS,
    minDistanceM: row.minDistanceM,
    isActive: row.isActive,
  };
}
