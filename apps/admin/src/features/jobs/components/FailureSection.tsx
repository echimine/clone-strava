"use client";

import { Button } from "@repo/ui/components/button";
import type { ColumnDef } from "@tanstack/react-table";
import { toast } from "sonner";
import { DataTable } from "@/components/DataTable";
import type { FailureKind, FailureRows } from "@/features/jobs/api";
import { BatchRelaunchButton } from "@/features/jobs/components/BatchRelaunchButton";
import { useFailureActions, useFailureList } from "@/features/jobs/hooks/useFailures";
import { useListUrlState } from "@/lib/list-url-state";

export type FailureCopy = {
  title: string;
  /** « Retraiter » or « Recalculer ». */
  verb: string;
  emptyMessage: string;
  itemLabel: string;
  /** What the batch confirmation says will happen to `count` failures. */
  describeBatch: (count: number) => string;
  /** The toast after a unit relaunch. */
  relaunchedOne: string;
};

/**
 * One list of the "Échecs" tab (ADR-038 §14), its page in the URL under its own prefix: each
 * row relaunches through its domain action, and « {verb} les N en échec » relaunches the batch.
 */
export function FailureSection<Kind extends FailureKind>({
  kind,
  copy,
  columns,
}: {
  kind: Kind;
  copy: FailureCopy;
  columns: ColumnDef<FailureRows[Kind]>[];
}) {
  const list = useListUrlState({ prefix: kind });
  const { data, isLoading, isPlaceholderData } = useFailureList(kind, { page: list.page, pageSize: list.pageSize });
  const actions = useFailureActions(kind);
  const total = data?.total ?? 0;

  const actionColumn: ColumnDef<FailureRows[Kind]> = {
    id: "actions",
    header: "",
    cell: ({ row }) => (
      <Button
        size="sm"
        variant="secondary"
        disabled={actions.one.isPending}
        onClick={() =>
          actions.one.mutate(row.original.id, {
            onSuccess: () => toast.success(copy.relaunchedOne),
            onError: (error) => toast.error(error.message),
          })
        }
      >
        {copy.verb}
      </Button>
    ),
  };

  return (
    <section className="flex flex-col gap-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h2 className="text-lg font-semibold">
          {copy.title} <span className="text-muted-foreground">({total})</span>
        </h2>
        <div className="flex items-center gap-3">
          {actions.all.data ? (
            <span className="text-sm text-muted-foreground">{actions.all.data.relaunched} relancé(s)</span>
          ) : null}
          <BatchRelaunchButton
            label={`${copy.verb} les ${total} en échec`}
            count={total}
            title={`${copy.verb} les ${total} en échec`}
            description={copy.describeBatch(total)}
            confirmLabel={copy.verb}
            pending={actions.all.isPending}
            onConfirm={() =>
              actions.all.mutate(undefined, {
                onSuccess: ({ relaunched }) => toast.success(`${relaunched} relancé(s)`),
                onError: (error) => toast.error(error.message),
              })
            }
          />
        </div>
      </div>
      <DataTable<FailureRows[Kind]>
        columns={[...columns, actionColumn]}
        data={data?.items ?? []}
        isLoading={isLoading}
        emptyMessage={copy.emptyMessage}
        getRowId={(row) => row.id}
        pagination={{ list, total, itemLabel: copy.itemLabel, disabled: isPlaceholderData }}
      />
    </section>
  );
}
