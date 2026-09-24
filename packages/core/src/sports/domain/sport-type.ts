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
