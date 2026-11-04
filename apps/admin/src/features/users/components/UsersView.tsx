"use client";

import {
  adminUserMethodFilterSchema,
  adminUserPremiumFilterSchema,
  adminUserStateSchema,
  sortOrderSchema,
  userRoleSchema,
} from "@repo/contracts";
import { UserFilters } from "@/features/users/components/UserFilters";
import { UserTable } from "@/features/users/components/UserTable";
import { useUsers } from "@/features/users/hooks/useUsers";
import { useListUrlState } from "@/lib/list-url-state";

/**
 * The backoffice users list (ADR-038 §5): search, filters and sort in the URL, newest sign-up
 * first by default.
 */
export function UsersView() {
  const list = useListUrlState();
  const sort = list.get("sort") === "lastActivityAt" ? "lastActivityAt" : undefined;
  const premium = adminUserPremiumFilterSchema.safeParse(list.get("premium")).data;
  const { data, isLoading, isPlaceholderData } = useUsers({
    page: list.page,
    pageSize: list.pageSize,
    q: list.get("q"),
    role: userRoleSchema.safeParse(list.get("role")).data,
    state: adminUserStateSchema.safeParse(list.get("state")).data,
    premium,
    method: adminUserMethodFilterSchema.safeParse(list.get("method")).data,
    from: list.get("from"),
    to: list.get("to"),
    sort,
    order: sortOrderSchema.safeParse(list.get("order")).data,
  });

  return (
    <div className="flex flex-col gap-4">
      <UserFilters list={list} />
      <UserTable
        data={data?.items ?? []}
        isLoading={isLoading}
        showPremiumEnd={premium !== undefined}
        pagination={{ list, total: data?.total ?? 0, itemLabel: "utilisateurs", disabled: isPlaceholderData }}
      />
    </div>
  );
}
