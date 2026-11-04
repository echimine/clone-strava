"use client";

import { ADMIN_DEFAULT_PAGE_SIZE, ADMIN_PAGE_SIZES, type AdminPageSize } from "@repo/contracts";
import { usePathname, useRouter, useSearchParams } from "next/navigation";

export type ListFilters = Record<string, string | undefined>;

export interface ListUrlState {
  page: number;
  pageSize: AdminPageSize;
  /** A filter's value (`q`, `sort`, `order`, `from`, `to`, the list's own filters), if set. */
  get: (name: string) => string | undefined;
  /** Sets or clears filters (`undefined` or `""` clears) and goes back to the first page. */
  setFilters: (patch: ListFilters) => void;
  setPage: (page: number) => void;
  setPageSize: (pageSize: AdminPageSize) => void;
}

/**
 * A backoffice list's state, held in the URL (ADR-013, ADR-038 §2): a filtered page can be shared,
 * reloaded, or opened pre-filled from a link ("Voir ses Activités"). `prefix` namespaces the
 * parameters of a list embedded in another page (`historyPage`, `historyAction`…), so two lists
 * of one page keep their own state. Page 1 and the default page size (50 unless
 * `defaultPageSize` says otherwise) are left out of the URL.
 */
export function useListUrlState(
  options: { prefix?: string; defaultPageSize?: AdminPageSize } = {},
): ListUrlState {
  const defaultPageSize = options.defaultPageSize ?? ADMIN_DEFAULT_PAGE_SIZE;
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const key = (name: string) =>
    options.prefix ? `${options.prefix}${name.charAt(0).toUpperCase()}${name.slice(1)}` : name;

  const page = Number.parseInt(searchParams.get(key("page")) ?? "", 10);
  const pageSize = Number.parseInt(searchParams.get(key("pageSize")) ?? "", 10);

  function navigate(patch: ListFilters, resetPage: boolean) {
    const params = new URLSearchParams(searchParams.toString());
    for (const [name, value] of Object.entries(patch)) {
      if (value === undefined || value === "") {
        params.delete(key(name));
      } else {
        params.set(key(name), value);
      }
    }
    if (resetPage) {
      params.delete(key("page"));
    }
    const query = params.toString();
    router.push(query ? `${pathname}?${query}` : pathname, { scroll: false });
  }

  return {
    page: Number.isInteger(page) && page >= 1 ? page : 1,
    pageSize: (ADMIN_PAGE_SIZES as readonly number[]).includes(pageSize)
      ? (pageSize as AdminPageSize)
      : defaultPageSize,
    get: (name) => searchParams.get(key(name)) || undefined,
    setFilters: (patch) => navigate(patch, true),
    setPage: (next) => navigate({ page: next === 1 ? undefined : String(next) }, false),
    setPageSize: (next) =>
      navigate({ pageSize: next === defaultPageSize ? undefined : String(next) }, true),
  };
}
