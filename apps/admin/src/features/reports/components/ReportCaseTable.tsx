"use client";

import type { AdminReportCaseListItem } from "@repo/contracts";
import { Avatar, AvatarFallback, AvatarImage } from "@repo/ui/components/avatar";
import { Badge } from "@repo/ui/components/badge";
import type { ColumnDef } from "@tanstack/react-table";
import Link from "next/link";
import { useState } from "react";
import { DataTable, type DataTableProps } from "@/components/DataTable";
import {
  ageLabel,
  caseStatusLabels,
  caseStatusVariants,
  formatDateTime,
  isOverdue,
  reasonsLabel,
  reportTargetLabels,
} from "@/features/reports/lib/labels";

function columns(now: number, closed: boolean): ColumnDef<AdminReportCaseListItem>[] {
  return [
    { id: "type", header: "Type", cell: ({ row }) => reportTargetLabels[row.original.targetType] },
    {
      id: "preview",
      header: "Aperçu",
      cell: ({ row }) => {
        const item = row.original;
        return (
          <Link href={`/reports/${item.id}`} className="flex items-center gap-2 underline-offset-4 hover:underline">
            {item.targetType === "athlete" ? (
              <Avatar className="size-6">
                {item.author.avatarUrl ? <AvatarImage src={item.author.avatarUrl} alt="" /> : null}
                <AvatarFallback className="text-xs">{(item.author.displayName ?? "?").slice(0, 1)}</AvatarFallback>
              </Avatar>
            ) : null}
            <span className="max-w-80 truncate">{item.preview ?? "Voir le dossier"}</span>
          </Link>
        );
      },
    },
    {
      id: "author",
      header: "Auteur",
      cell: ({ row }) =>
        row.original.author.displayName === null ? (
          <span className="text-muted-foreground">Compte supprimé</span>
        ) : (
          <Link href={`/users/${row.original.author.id}`} className="underline-offset-4 hover:underline">
            {row.original.author.displayName || row.original.author.id.slice(0, 8)}
          </Link>
        ),
    },
    { id: "count", header: "Signalements", cell: ({ row }) => row.original.reportCount },
    { id: "reasons", header: "Motifs", cell: ({ row }) => reasonsLabel(row.original.reasons) },
    closed
      ? {
          id: "outcome",
          header: "Issue",
          cell: ({ row }) => (
            <span className="flex flex-col gap-1">
              <Badge variant={caseStatusVariants[row.original.status]}>{caseStatusLabels[row.original.status]}</Badge>
              {row.original.closedAt ? (
                <span className="text-xs text-muted-foreground">{formatDateTime(row.original.closedAt)}</span>
              ) : null}
            </span>
          ),
        }
      : {
          id: "age",
          header: "Âge",
          cell: ({ row }) => (
            <span className="flex items-center gap-2">
              {ageLabel(row.original.openedAt, now)}
              {isOverdue(row.original.openedAt, now) ? <Badge variant="destructive">plus de 24 h</Badge> : null}
            </span>
          ),
        },
  ];
}

/** The moderation queue's table (ADR-038 §10): one row per case; an open case past 24 h gets a red badge. */
export function ReportCaseTable({
  data,
  isLoading,
  pagination,
  closed,
}: Pick<DataTableProps<AdminReportCaseListItem>, "data" | "isLoading" | "pagination"> & { closed: boolean }) {
  // Ages are read against the time the page opened, not re-rendered every minute.
  const [now] = useState(() => Date.now());
  return (
    <DataTable
      columns={columns(now, closed)}
      data={data}
      isLoading={isLoading}
      emptyMessage={closed ? "Aucun dossier clos." : "Aucun signalement à traiter."}
      getRowId={(row) => row.id}
      pagination={pagination}
    />
  );
}
