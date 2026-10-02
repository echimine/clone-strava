import type { ActivityImport, ActivityImportFormat, ActivityImportStatus } from "@repo/contracts";

/** Fields of an `activity_import` row the wire shape needs (domain stays repository-free, ADR-021 §6). */
export interface ActivityImportRowFields {
  id: string;
  format: ActivityImportFormat;
  originalFileName: string;
  status: ActivityImportStatus;
  activityId: string | null;
  error: string | null;
  createdAt: Date;
  processedAt: Date | null;
}

/** `activity_import` row -> wire shape (ADR-028 §3). */
export function toActivityImport(row: ActivityImportRowFields): ActivityImport {
  return {
    id: row.id,
    format: row.format,
    fileName: row.originalFileName,
    status: row.status,
    activityId: row.activityId ?? undefined,
    error: (row.error as ActivityImport["error"]) ?? undefined,
    createdAt: row.createdAt.toISOString(),
    processedAt: row.processedAt?.toISOString(),
  };
}
