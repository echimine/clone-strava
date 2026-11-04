"use client";

import type { AdminFailedActivity, AdminFailedImport, AdminStaleActivity } from "@repo/contracts";
import type { ColumnDef } from "@tanstack/react-table";
import Link from "next/link";
import { FailureSection } from "@/features/jobs/components/FailureSection";
import { athleteName, formatDateTime, sportLabel } from "@/features/jobs/lib/labels";

const linkClass = "underline-offset-4 hover:underline";

function activityColumn<Row extends { id: string; title: string }>(): ColumnDef<Row> {
  return {
    id: "activity",
    header: "Activité",
    cell: ({ row }) => (
      <Link href={`/activities/${row.original.id}`} className={`font-medium ${linkClass}`}>
        {row.original.title}
      </Link>
    ),
  };
}

function athleteColumn<Row extends { athlete: { id: string; displayName: string } }>(): ColumnDef<Row> {
  return {
    id: "athlete",
    header: "Athlète",
    cell: ({ row }) => (
      <Link href={`/users/${row.original.athlete.id}`} className={linkClass}>
        {athleteName(row.original.athlete)}
      </Link>
    ),
  };
}

const code = (value: string | null) =>
  value === null ? "—" : <code className="font-mono text-xs">{value}</code>;

const failedActivityColumns: ColumnDef<AdminFailedActivity>[] = [
  activityColumn(),
  athleteColumn(),
  { id: "sport", header: "Sport", cell: ({ row }) => sportLabel(row.original.sportTypeCode) },
  { id: "error", header: "Erreur", cell: ({ row }) => code(row.original.processingError) },
  { id: "attempts", header: "Tentatives", cell: ({ row }) => String(row.original.processingAttempts) },
  { id: "createdAt", header: "Créée le", cell: ({ row }) => formatDateTime(row.original.createdAt) },
];

const failedImportColumns: ColumnDef<AdminFailedImport>[] = [
  { id: "file", header: "Fichier", cell: ({ row }) => row.original.fileName },
  athleteColumn(),
  { id: "format", header: "Format", cell: ({ row }) => row.original.format.toUpperCase() },
  { id: "error", header: "Erreur", cell: ({ row }) => code(row.original.error) },
  { id: "attempts", header: "Tentatives", cell: ({ row }) => String(row.original.attempts) },
  { id: "createdAt", header: "Importé le", cell: ({ row }) => formatDateTime(row.original.createdAt) },
];

const staleActivityColumns: ColumnDef<AdminStaleActivity>[] = [
  activityColumn(),
  athleteColumn(),
  { id: "sport", header: "Sport", cell: ({ row }) => sportLabel(row.original.sportTypeCode) },
  {
    id: "computedFor",
    header: "Valeurs calculées pour",
    cell: ({ row }) => sportLabel(row.original.computedForSportTypeCode),
  },
  { id: "updatedAt", header: "Modifiée le", cell: ({ row }) => formatDateTime(row.original.updatedAt) },
];

/**
 * The "Échecs" tab (ADR-038 §14), the business view: failed Activities and imports, and failed
 * recomputations (processed Activities whose values were computed for another sport).
 */
export function FailuresTab() {
  return (
    <div className="flex flex-col gap-8">
      <FailureSection
        kind="activities"
        columns={failedActivityColumns}
        copy={{
          title: "Activités en échec",
          verb: "Retraiter",
          emptyMessage: "Aucune Activité en échec.",
          itemLabel: "activités",
          describeBatch: (count) => `${count} Activités en échec seront renvoyées en traitement.`,
          relaunchedOne: "Activité renvoyée en traitement",
        }}
      />
      <FailureSection
        kind="imports"
        columns={failedImportColumns}
        copy={{
          title: "Imports en échec",
          verb: "Retraiter",
          emptyMessage: "Aucun import en échec.",
          itemLabel: "imports",
          describeBatch: (count) => `${count} imports en échec seront renvoyés en traitement.`,
          relaunchedOne: "Import renvoyé en traitement",
        }}
      />
      <FailureSection
        kind="recomputes"
        columns={staleActivityColumns}
        copy={{
          title: "Recalculs en échec",
          verb: "Recalculer",
          emptyMessage: "Aucun recalcul en échec.",
          itemLabel: "activités",
          describeBatch: (count) =>
            `Les valeurs officielles de ${count} Activités seront recalculées pour leur sport.`,
          relaunchedOne: "Recalcul relancé",
        }}
      />
    </div>
  );
}
