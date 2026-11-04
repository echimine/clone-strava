"use client";

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
import type { ListUrlState } from "@/lib/list-url-state";
import { DataTablePagination } from "./DataTablePagination";

export type DataTableProps<Row> = {
  columns: ColumnDef<Row>[];
  data: Row[];
  isLoading: boolean;
  /** Shown when the page has no row. */
  emptyMessage: string;
  getRowId?: (row: Row) => string;
  /**
   * Server-side pagination (ADR-038 §2) driven by the list's URL state: numbered pages, the
   * total and the page size. `disabled` while a new page loads (`isPlaceholderData`).
   */
  pagination?: { list: ListUrlState; total: number; itemLabel: string; disabled?: boolean };
};

/**
 * The backoffice's one table (ADR-013 "Tables and filters", ADR-038 §2): TanStack Table for the
 * columns, shadcn's `Table` for the markup, rows sorted and paged by the API. Every admin list
 * renders through it; its filters and page live in the URL (`useListUrlState`).
 */
export function DataTable<Row>({
  columns,
  data,
  isLoading,
  emptyMessage,
  getRowId,
  pagination,
}: DataTableProps<Row>) {
  // TanStack Table is not compatible with React Compiler memoization; the compiler skips this component.
  // eslint-disable-next-line react-hooks/incompatible-library
  const table = useReactTable({
    data,
    columns,
    getCoreRowModel: getCoreRowModel(),
    getRowId,
    manualPagination: true,
    manualSorting: true,
  });

  return (
    <div className="flex flex-col gap-4">
      <div className="rounded-md border">
        <Table>
          <TableHeader>
            {table.getHeaderGroups().map((headerGroup) => (
              <TableRow key={headerGroup.id}>
                {headerGroup.headers.map((header) => (
                  <TableHead key={header.id}>
                    {header.isPlaceholder ? null : flexRender(header.column.columnDef.header, header.getContext())}
                  </TableHead>
                ))}
              </TableRow>
            ))}
          </TableHeader>
          <TableBody>
            {isLoading ? (
              Array.from({ length: 5 }).map((_, index) => (
                <TableRow key={index}>
                  {table.getVisibleLeafColumns().map((column) => (
                    <TableCell key={column.id}>
                      <Skeleton className="h-4 w-24" />
                    </TableCell>
                  ))}
                </TableRow>
              ))
            ) : table.getRowModel().rows.length === 0 ? (
              <TableRow>
                <TableCell colSpan={columns.length} className="text-center text-muted-foreground">
                  {emptyMessage}
                </TableCell>
              </TableRow>
            ) : (
              table.getRowModel().rows.map((row) => (
                <TableRow key={row.id}>
                  {row.getVisibleCells().map((cell) => (
                    <TableCell key={cell.id} className="align-top">
                      {flexRender(cell.column.columnDef.cell, cell.getContext())}
                    </TableCell>
                  ))}
                </TableRow>
              ))
            )}
          </TableBody>
        </Table>
      </div>
      {pagination ? (
        <DataTablePagination
          page={pagination.list.page}
          pageSize={pagination.list.pageSize}
          total={pagination.total}
          itemLabel={pagination.itemLabel}
          disabled={pagination.disabled}
          onPageChange={pagination.list.setPage}
          onPageSizeChange={pagination.list.setPageSize}
        />
      ) : null}
    </div>
  );
}
