"use client";

import type { AdminQueueJob } from "@repo/contracts";
import { Button } from "@repo/ui/components/button";
import type { ColumnDef } from "@tanstack/react-table";
import { useState } from "react";
import { toast } from "sonner";
import { DataTable } from "@/components/DataTable";
import { JobDetailDialog } from "@/features/jobs/components/JobDetailDialog";
import { useFailedJobs, useQueueActions } from "@/features/jobs/hooks/useQueues";
import { formatDateTime } from "@/features/jobs/lib/labels";
import { useListUrlState } from "@/lib/list-url-state";

/**
 * The failed jobs of one queue, newest first (ADR-038 §14), paged in the URL (`jobsPage`):
 * « Relancer » one with its attempts reset, except `process-activity` and `import-activity`,
 * which « Retraiter » relaunches from the "Échecs" tab. « Détail » opens it read-only.
 */
export function QueueJobsSection({ queue }: { queue: string }) {
  const list = useListUrlState({ prefix: "jobs" });
  const { data, isLoading, isPlaceholderData } = useFailedJobs(queue, { page: list.page, pageSize: list.pageSize });
  const { retry } = useQueueActions();
  const [openJobId, setOpenJobId] = useState<string>();

  const columns: ColumnDef<AdminQueueJob>[] = [
    { id: "name", header: "Job", cell: ({ row }) => <code className="font-mono text-xs">{row.original.name}</code> },
    {
      id: "id",
      header: "Id",
      cell: ({ row }) => <span className="break-all font-mono text-xs text-muted-foreground">{row.original.id}</span>,
    },
    { id: "reason", header: "Raison", cell: ({ row }) => row.original.failedReason ?? "—" },
    {
      id: "attempts",
      header: "Tentatives",
      cell: ({ row }) => `${row.original.attemptsMade}/${row.original.maxAttempts}`,
    },
    { id: "finishedAt", header: "Échoué le", cell: ({ row }) => formatDateTime(row.original.finishedAt) },
    {
      id: "actions",
      header: "",
      cell: ({ row }) => (
        <div className="flex flex-wrap items-center justify-end gap-2">
          {row.original.retryRefused ? (
            <span className="text-xs text-muted-foreground">Retraiter depuis Échecs</span>
          ) : (
            <Button
              size="sm"
              variant="secondary"
              disabled={retry.isPending}
              onClick={() =>
                retry.mutate(
                  { queue, id: row.original.id },
                  {
                    onSuccess: () => toast.success("Job relancé"),
                    onError: (error) => toast.error(error.message),
                  },
                )
              }
            >
              Relancer
            </Button>
          )}
          <Button size="sm" variant="ghost" onClick={() => setOpenJobId(row.original.id)}>
            Détail
          </Button>
        </div>
      ),
    },
  ];

  return (
    <section className="flex flex-col gap-3">
      <h2 className="text-lg font-semibold">
        Jobs en échec de <span className="font-mono">{queue}</span>
      </h2>
      <DataTable
        columns={columns}
        data={data?.items ?? []}
        isLoading={isLoading}
        emptyMessage="Aucun job en échec dans cette file."
        getRowId={(row) => row.id}
        pagination={{ list, total: data?.total ?? 0, itemLabel: "jobs", disabled: isPlaceholderData }}
      />
      <JobDetailDialog queue={queue} jobId={openJobId} onClose={() => setOpenJobId(undefined)} />
    </section>
  );
}
