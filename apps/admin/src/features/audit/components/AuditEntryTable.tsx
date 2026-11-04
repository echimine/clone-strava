"use client";

import type { AuditEntry, AuditPerson } from "@repo/contracts";
import { Button } from "@repo/ui/components/button";
import type { ColumnDef } from "@tanstack/react-table";
import { FilterIcon } from "lucide-react";
import Link from "next/link";
import { DataTable, type DataTableProps } from "@/components/DataTable";
import { auditActionLabels, auditTargetLabels, formatParisDateTime, targetHref } from "@/features/audit/lib/labels";

/** An author or athlete concerned: "Système", "Compte supprimé", or a link to their sheet. */
function Person({ person }: { person: AuditPerson | null }) {
  if (person === null) {
    return <span className="text-muted-foreground">Système</span>;
  }
  if (person.displayName === null) {
    return <span className="text-muted-foreground italic">Compte supprimé</span>;
  }
  return (
    <Link href={`/users/${person.id}`} className="underline-offset-4 hover:underline">
      {person.displayName}
    </Link>
  );
}

function Target({ target }: { target: AuditEntry["target"] }) {
  const label = auditTargetLabels[target.type];
  const href = target.id !== null && target.exists ? targetHref(target.type, target.id) : null;
  if (target.id === null) {
    return <span>{label}</span>;
  }
  return (
    <span className="flex flex-col">
      <span>{label}</span>
      {href ? (
        <Link href={href} className="font-mono text-xs underline-offset-4 hover:underline">
          {target.id.slice(0, 8)}
        </Link>
      ) : (
        <span className="font-mono text-xs text-muted-foreground" title={target.id}>
          {target.id.slice(0, 8)}
          {target.exists ? "" : " (supprimé)"}
        </span>
      )}
    </span>
  );
}

function Details({ entry }: { entry: AuditEntry }) {
  if (entry.details === null && entry.requestId === null) {
    return null;
  }
  return (
    <details className="text-xs">
      <summary className="cursor-pointer text-muted-foreground">Détails</summary>
      <pre className="mt-1 max-w-xs overflow-x-auto whitespace-pre-wrap font-mono">
        {JSON.stringify({ ...entry.details, ...(entry.requestId ? { requestId: entry.requestId } : {}) }, null, 2)}
      </pre>
    </details>
  );
}

function columns(onFilterSubject?: (subject: AuditPerson) => void, withSubject = true): ColumnDef<AuditEntry>[] {
  return [
    {
      id: "createdAt",
      header: "Date",
      cell: ({ row }) => <span className="whitespace-nowrap">{formatParisDateTime(row.original.createdAt)}</span>,
    },
    { id: "actor", header: "Auteur", cell: ({ row }) => <Person person={row.original.actor} /> },
    { id: "action", header: "Action", cell: ({ row }) => auditActionLabels[row.original.action] },
    { id: "target", header: "Cible", cell: ({ row }) => <Target target={row.original.target} /> },
    ...(withSubject
      ? [
          {
            id: "subject",
            header: "Athlète concerné",
            cell: ({ row }) => {
              const subject = row.original.subject;
              return (
                <span className="flex items-center gap-1">
                  <Person person={subject} />
                  {subject && onFilterSubject ? (
                    <Button
                      variant="ghost"
                      size="icon"
                      className="size-6"
                      aria-label={`Filtrer sur ${subject.displayName ?? "ce compte supprimé"}`}
                      onClick={() => onFilterSubject(subject)}
                    >
                      <FilterIcon className="size-3" />
                    </Button>
                  ) : null}
                </span>
              );
            },
          } satisfies ColumnDef<AuditEntry>,
        ]
      : []),
    {
      id: "reason",
      header: "Motif",
      cell: ({ row }) => <span className="whitespace-pre-wrap">{row.original.reason ?? ""}</span>,
    },
    { id: "details", header: "", cell: ({ row }) => <Details entry={row.original} /> },
  ];
}

type AuditEntryTableProps = Omit<DataTableProps<AuditEntry>, "columns" | "getRowId" | "emptyMessage"> & {
  /** Offers to filter the list on an entry's athlete concerned. */
  onFilterSubject?: (subject: AuditPerson) => void;
  /** Hides the athlete concerned, when the list is about one athlete (Historique). */
  withSubject?: boolean;
};

/** Journal entries in the shared table (ADR-038 §3): date, author, action, target, athlete, reason. */
export function AuditEntryTable({ onFilterSubject, withSubject = true, ...props }: AuditEntryTableProps) {
  return (
    <DataTable
      {...props}
      columns={columns(onFilterSubject, withSubject)}
      getRowId={(entry) => entry.id}
      emptyMessage="Aucune entrée."
    />
  );
}
