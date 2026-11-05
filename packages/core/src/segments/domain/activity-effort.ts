/** An effort of an Activity on a Segment, as the backoffice shows it read-only (ADR-038 §11). */
export interface ActivityEffortRecord {
  id: string;
  segmentId: string;
  segmentName: string;
  elapsedTimeS: number;
  startedAt: Date;
}
