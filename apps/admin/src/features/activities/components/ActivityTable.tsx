"use client";

import type { AdminActivityListItem } from "@repo/contracts";
import { Badge } from "@repo/ui/components/badge";
import type { ColumnDef } from "@tanstack/react-table";
import Link from "next/link";
import { DataTable, type DataTableProps } from "@/components/DataTable";
import {
  formatDateTime,
  formatDistance,
  sourceLabels,
  sportLabel,
  statusLabels,
  statusVariants,
  visibilityLabels,
} from "@/features/activities/lib/labels";

const columns: ColumnDef<AdminActivityListItem>[] = [
  {
    id: "title",
    header: "Activité",
    cell: ({ row }) => (
      <Link href={`/activities/${row.original.id}`} className="font-medium underline-offset-4 hover:underline">
        {row.original.title}
      </Link>
    ),
  },
  {
    id: "athlete",
    header: "Athlète",
    cell: ({ row }) => (
      <Link href={`/users/${row.original.athlete.id}`} className="underline-offset-4 hover:underline">
        {row.original.athlete.displayName || row.original.athlete.id.slice(0, 8)}
      </Link>
    ),
  },
  { id: "sport", header: "Sport", cell: ({ row }) => sportLabel(row.original.sportTypeCode) },
  {
    id: "status",
    header: "Statut",
    cell: ({ row }) => (
      <Badge variant={statusVariants[row.original.processingStatus]}>{statusLabels[row.original.processingStatus]}</Badge>
    ),
  },
  { id: "source", header: "Source", cell: ({ row }) => sourceLabels[row.original.source] },
  { id: "visibility", header: "Visibilité", cell: ({ row }) => visibilityLabels[row.original.visibility] },
  { id: "distance", header: "Distance", cell: ({ row }) => formatDistance(row.original.distanceM) },
  { id: "startedAt", header: "Début", cell: ({ row }) => formatDateTime(row.original.startedAt) },
  { id: "createdAt", header: "Créée le", cell: ({ row }) => formatDateTime(row.original.createdAt) },
];

/** The Activities list's table (ADR-038 §11), newest created first. */
export function ActivityTable({
  data,
  isLoading,
  pagination,
}: Pick<DataTableProps<AdminActivityListItem>, "data" | "isLoading" | "pagination">) {
  return (
    <DataTable
      columns={columns}
      data={data}
      isLoading={isLoading}
      emptyMessage="Aucune activité."
      getRowId={(row) => row.id}
      pagination={pagination}
    />
  );
}
