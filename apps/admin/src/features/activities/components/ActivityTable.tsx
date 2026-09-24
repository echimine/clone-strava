"use client";

import type { ActivitySummary, ProcessingStatus, Visibility } from "@repo/contracts";
import { Badge } from "@repo/ui/components/badge";
import { Skeleton } from "@repo/ui/components/skeleton";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@repo/ui/components/table";
import {
  flexRender,
  getCoreRowModel,
  useReactTable,
  type ColumnDef,
} from "@tanstack/react-table";

const statusLabels: Record<ProcessingStatus, string> = {
  pending: "En attente",
  processing: "En cours de traitement",
  processed: "Traitée",
  failed: "Échec",
};

const statusVariants: Record<ProcessingStatus, "secondary" | "default" | "destructive"> = {
  pending: "secondary",
  processing: "secondary",
  processed: "default",
  failed: "destructive",
};

const visibilityLabels: Record<Visibility, string> = {
  public: "Publique",
  followers: "Abonnés",
  private: "Privée",
};

const columns: ColumnDef<ActivitySummary>[] = [
  {
    accessorKey: "id",
    header: "Identifiant",
    cell: ({ getValue }) => (
      <span className="font-mono text-xs text-muted-foreground">{getValue<string>()}</span>
    ),
  },
  {
    accessorKey: "sportTypeCode",
    header: "Sport",
  },
  {
    accessorKey: "visibility",
    header: "Visibilité",
    cell: ({ getValue }) => visibilityLabels[getValue<Visibility>()],
  },
  {
    accessorKey: "processingStatus",
    header: "Statut",
    cell: ({ getValue }) => {
      const status = getValue<ProcessingStatus>();
      return <Badge variant={statusVariants[status]}>{statusLabels[status]}</Badge>;
    },
  },
];

type ActivityTableProps = {
  activities: ActivitySummary[];
  isLoading: boolean;
};

/** Generic data table pattern for the feature (ADR-013 §"Where to put a component"). */
export function ActivityTable({ activities, isLoading }: ActivityTableProps) {
  // TanStack Table is not compatible with React Compiler memoization; the compiler skips this component.
  // eslint-disable-next-line react-hooks/incompatible-library
  const table = useReactTable({
    data: activities,
    columns,
    getCoreRowModel: getCoreRowModel(),
  });

  return (
    <Table>
      <TableHeader>
        {table.getHeaderGroups().map((headerGroup) => (
          <TableRow key={headerGroup.id}>
            {headerGroup.headers.map((header) => (
              <TableHead key={header.id}>
                {header.isPlaceholder
                  ? null
                  : flexRender(header.column.columnDef.header, header.getContext())}
              </TableHead>
            ))}
          </TableRow>
        ))}
      </TableHeader>
      <TableBody>
        {isLoading ? (
          Array.from({ length: 5 }).map((_, index) => (
            <TableRow key={index}>
              {columns.map((column) => (
                <TableCell key={String(column.id ?? (column as { accessorKey?: string }).accessorKey)}>
                  <Skeleton className="h-4 w-24" />
                </TableCell>
              ))}
            </TableRow>
          ))
        ) : table.getRowModel().rows.length === 0 ? (
          <TableRow>
            <TableCell colSpan={columns.length} className="text-center text-muted-foreground">
              Aucune activité.
            </TableCell>
          </TableRow>
        ) : (
          table.getRowModel().rows.map((row) => (
            <TableRow key={row.id}>
              {row.getVisibleCells().map((cell) => (
                <TableCell key={cell.id}>
                  {flexRender(cell.column.columnDef.cell, cell.getContext())}
                </TableCell>
              ))}
            </TableRow>
          ))
        )}
      </TableBody>
    </Table>
  );
}
