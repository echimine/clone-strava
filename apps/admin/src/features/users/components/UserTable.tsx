"use client";

import type { AdminUserListItem } from "@repo/contracts";
import { Badge } from "@repo/ui/components/badge";
import type { ColumnDef } from "@tanstack/react-table";
import Link from "next/link";
import { DataTable, type DataTableProps } from "@/components/DataTable";
import { UserAvatar } from "@/features/users/components/UserIdentity";
import { banLabel, formatDate, formatDateTime, methodLabels, roleLabels } from "@/features/users/lib/labels";
import { premiumStateLabels } from "@/lib/premium-labels";

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
    cell: ({ row }) => premiumCell(row.original),
  },
  {
    id: "state",
    header: "État",
    cell: ({ row }) =>
      row.original.ban ? <Badge variant="destructive">{banLabel(row.original.ban)}</Badge> : "Actif",
  },
];

/** Premium now as a badge (« Payant », « Premium offert »…); else « Expiré », or a dash when never. */
function premiumCell(user: AdminUserListItem) {
  if (user.isPremium) {
    return <Badge>{premiumStateLabels[user.premiumState]}</Badge>;
  }
  return user.premiumState === "never" ? "—" : premiumStateLabels[user.premiumState];
}

/** « Fin »: the end of the Premium period, shown while the Premium filter is set (ADR-038 §12). */
const premiumEndColumn: ColumnDef<AdminUserListItem> = {
  id: "premiumEndsAt",
  header: "Fin",
  cell: ({ row }) => formatDate(row.original.premiumEndsAt),
};

const withPremiumEnd = columns.flatMap((column) => (column.id === "premium" ? [column, premiumEndColumn] : [column]));

/** The users list's table (ADR-038 §5); `showPremiumEnd` adds the « Fin » column. */
export function UserTable({
  data,
  isLoading,
  pagination,
  showPremiumEnd = false,
}: Pick<DataTableProps<AdminUserListItem>, "data" | "isLoading" | "pagination"> & { showPremiumEnd?: boolean }) {
  return (
    <DataTable
      columns={showPremiumEnd ? withPremiumEnd : columns}
      data={data}
      isLoading={isLoading}
      emptyMessage="Aucun utilisateur."
      getRowId={(row) => row.athlete.id}
      pagination={pagination}
    />
  );
}
