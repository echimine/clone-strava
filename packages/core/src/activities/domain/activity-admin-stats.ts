/** The "À traiter" counts the `activities` module owns (ADR-038 §15). */
export interface ActivityFailureCounts {
  /** Activities whose processing failed (`processing_status = failed`). */
  failedActivities: number;
  /** Imports failed since the given instant. */
  failedImports: number;
}

/** The "Croissance" counts the `activities` module owns over one period (ADR-038 §15). */
export interface ActivityGrowthCounts {
  /** Activities started in the period, by source. */
  recorded: number;
  imported: number;
  manual: number;
  /** Active athletes: at least one Activity started in the period (glossary). */
  activeAthletes: number;
  /** Media added in the period. */
  media: number;
}
