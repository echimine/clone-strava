"use client";

import type { AdminUserListItem } from "@repo/contracts";
import { Badge } from "@repo/ui/components/badge";
import type { ColumnDef } from "@tanstack/react-table";
import Link from "next/link";
import { DataTable, type DataTableProps } from "@/components/DataTable";
import { UserAvatar } from "@/features/users/components/UserIdentity";
import { banLabel, formatDate, formatDateTime, methodLabels, roleLabels } from "@/features/users/lib/labels";

const columns: ColumnDef<AdminUserListItem>[] = [
  {
    id: "athlete",
    header: "Athlète",
    cell: ({ row }) => (
      <Link
        href={`/users/${row.original.athlete.id}`}
        className="flex items-center gap-2 font-medium underline-offset-4 hover:underline"
      >
        <UserAvatar athlete={row.original.athlete} className="size-7" />
        <span>{row.original.athlete.displayName || row.original.athlete.id.slice(0, 8)}</span>
        {row.original.role === "admin" ? <Badge variant="secondary">{roleLabels.admin}</Badge> : null}
      </Link>
    ),
  },
  { id: "email", header: "E-mail", cell: ({ row }) => row.original.email },
  { id: "createdAt", header: "Inscription", cell: ({ row }) => formatDate(row.original.createdAt) },
  {
    id: "methods",
    header: "Connexion",
    cell: ({ row }) => row.original.signInMethods.map((method) => methodLabels[method]).join(", "),
  },
  { id: "activityCount", header: "Activités", cell: ({ row }) => row.original.activityCount },
  {
    id: "lastActivityAt",
    header: "Dernière Activité",
    cell: ({ row }) => (row.original.lastActivityAt ? formatDateTime(row.original.lastActivityAt) : "—"),
  },
  {
    id: "premium",
    header: "Premium",
    cell: ({ row }) => (row.original.isPremium ? <Badge>Premium</Badge> : "—"),
  },
  {
    id: "state",
    header: "État",
    cell: ({ row }) =>
      row.original.ban ? <Badge variant="destructive">{banLabel(row.original.ban)}</Badge> : "Actif",
  },
];

/** The users list's table (ADR-038 §5). */
export function UserTable({
  data,
  isLoading,
  pagination,
}: Pick<DataTableProps<AdminUserListItem>, "data" | "isLoading" | "pagination">) {
  return (
    <DataTable
      columns={columns}
      data={data}
      isLoading={isLoading}
      emptyMessage="Aucun utilisateur."
      getRowId={(row) => row.athlete.id}
      pagination={pagination}
    />
  );
}
