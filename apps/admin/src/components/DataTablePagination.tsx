"use client";

import { ADMIN_PAGE_SIZES, type AdminPageSize } from "@repo/contracts";
import { Button } from "@repo/ui/components/button";
import { NativeSelect, NativeSelectOption } from "@repo/ui/components/native-select";
import {
  Pagination,
  PaginationContent,
  PaginationEllipsis,
  PaginationItem,
} from "@repo/ui/components/pagination";
import { ChevronLeftIcon, ChevronRightIcon } from "lucide-react";
import { useId } from "react";
import { pageCount, pageNumbers } from "@/lib/page-numbers";

export type DataTablePaginationProps = {
  page: number;
  pageSize: AdminPageSize;
  total: number;
  /** Plural noun of the rows, e.g. "entrées" (singular: drops the final "s"). */
  itemLabel: string;
  onPageChange: (page: number) => void;
  onPageSizeChange: (pageSize: AdminPageSize) => void;
  /** While the next page loads, the controls wait. */
  disabled?: boolean;
};

/** Numbered pagination with the total and the page size (25, 50 or 100), ADR-038 §2. */
export function DataTablePagination({
  page,
  pageSize,
  total,
  itemLabel,
  onPageChange,
  onPageSizeChange,
  disabled = false,
}: DataTablePaginationProps) {
  const sizeId = useId();
  const last = pageCount(total, pageSize);
  const noun = total > 1 ? itemLabel : itemLabel.replace(/s$/, "");

  return (
    <div className="flex flex-wrap items-center justify-between gap-3">
      <p className="text-sm text-muted-foreground">
        {total} {noun}
      </p>
      <div className="flex flex-wrap items-center gap-3">
        <div className="flex items-center gap-2 text-sm text-muted-foreground">
          <label htmlFor={sizeId}>Par page</label>
          <NativeSelect
            id={sizeId}
            size="sm"
            value={pageSize}
            onChange={(event) => onPageSizeChange(Number(event.target.value) as AdminPageSize)}
          >
            {ADMIN_PAGE_SIZES.map((size) => (
              <NativeSelectOption key={size} value={size}>
                {size}
              </NativeSelectOption>
            ))}
          </NativeSelect>
        </div>
        {last > 1 ? (
          <Pagination className="mx-0 w-auto">
            <PaginationContent>
              <PaginationItem>
                <Button
                  variant="ghost"
                  size="icon"
                  aria-label="Page précédente"
                  disabled={disabled || page <= 1}
                  onClick={() => onPageChange(page - 1)}
                >
                  <ChevronLeftIcon />
                </Button>
              </PaginationItem>
              {pageNumbers(Math.min(page, last), last).map((item, index) =>
                item === "gap" ? (
                  <PaginationItem key={`gap-${index}`}>
                    <PaginationEllipsis />
                  </PaginationItem>
                ) : (
                  <PaginationItem key={item}>
                    <Button
                      variant={item === page ? "outline" : "ghost"}
                      size="icon"
                      aria-label={`Page ${item}`}
                      aria-current={item === page ? "page" : undefined}
                      disabled={disabled}
                      onClick={() => onPageChange(item)}
                    >
                      {item}
                    </Button>
                  </PaginationItem>
                ),
              )}
              <PaginationItem>
                <Button
                  variant="ghost"
                  size="icon"
                  aria-label="Page suivante"
                  disabled={disabled || page >= last}
                  onClick={() => onPageChange(page + 1)}
                >
                  <ChevronRightIcon />
                </Button>
              </PaginationItem>
            </PaginationContent>
          </Pagination>
        ) : null}
      </div>
    </div>
  );
}
