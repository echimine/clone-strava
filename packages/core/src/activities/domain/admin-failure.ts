import type { ActivityImportErrorCode, ActivityImportFormat } from "@repo/contracts";

/** A `failed` Activity in the Jobs screen's "Échecs" tab (ADR-038 §14); the caller adds the athlete. */
export interface FailedActivityRow {
  id: string;
  userId: string;
  title: string;
  sportTypeCode: string;
  processingError: string | null;
  processingAttempts: number;
  startedAt: Date;
  createdAt: Date;
}

/** A `failed` import in the "Échecs" tab; the caller adds the athlete. */
export interface FailedImportRow {
  id: string;
  userId: string;
  format: ActivityImportFormat;
  fileName: string;
  error: ActivityImportErrorCode | null;
  attempts: number;
  createdAt: Date;
  processedAt: Date | null;
}

/**
 * A failed recomputation (ADR-033 §5, ADR-038 §14): a processed Activity whose official values
 * were computed for another sport than its own. The caller adds the athlete.
 */
export interface StaleActivityRow {
  id: string;
  userId: string;
  title: string;
  sportTypeCode: string;
  computedForSportTypeCode: string | null;
  startedAt: Date;
  updatedAt: Date;
}

/** One page of a failure list and the number of failures it pages over. */
export interface FailurePage<Row> {
  rows: Row[];
  total: number;
}
