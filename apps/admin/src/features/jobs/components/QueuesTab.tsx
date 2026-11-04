"use client";

import type { AdminQueue } from "@repo/contracts";
import { Badge } from "@repo/ui/components/badge";
import { Button } from "@repo/ui/components/button";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@repo/ui/components/table";
import { toast } from "sonner";
import { BatchRelaunchButton } from "@/features/jobs/components/BatchRelaunchButton";
import { QueueJobsSection } from "@/features/jobs/components/QueueJobsSection";
import { useQueueActions, useQueues } from "@/features/jobs/hooks/useQueues";
import { formatDateTime, schedulerRhythm } from "@/features/jobs/lib/labels";
import type { ListUrlState } from "@/lib/list-url-state";

const failed = (message: string) => (error: Error) => toast.error(error.message || message);

/**
 * The "Files" tab (ADR-038 §14), the technical view: each whitelisted queue with its counts,
 * pause state and schedulers; pause, resume, retry its failures. The failed jobs of the queue
 * chosen in the URL (`queue`) are listed below. Nothing here deletes a job.
 */
export function QueuesTab({ list }: { list: ListUrlState }) {
  const { data, isLoading } = useQueues();
  const actions = useQueueActions();
  const selected = list.get("queue");

  function row(queue: AdminQueue) {
    const { counts } = queue;
    return (
      <TableRow key={queue.name} data-state={queue.name === selected ? "selected" : undefined}>
        <TableCell className="font-mono text-sm">{queue.name}</TableCell>
        <TableCell>{queue.isPaused ? <Badge variant="secondary">En pause</Badge> : "Active"}</TableCell>
        <TableCell className="text-sm text-muted-foreground">
          {`${counts.waiting + counts.prioritized} en attente · ${counts.active} en cours · ${counts.delayed} différés · ${counts.completed} terminés`}
        </TableCell>
        <TableCell>
          <Button
            size="sm"
            variant={counts.failed > 0 ? "destructive" : "ghost"}
            onClick={() => list.setFilters({ queue: queue.name })}
          >
            {`${counts.failed} en échec`}
          </Button>
        </TableCell>
        <TableCell className="text-sm">
          {queue.schedulers.map((scheduler) => (
            <div key={scheduler.id}>
              {`${scheduler.id} · ${schedulerRhythm(scheduler)} · prochaine ${formatDateTime(scheduler.nextRunAt)}`}
            </div>
          ))}
        </TableCell>
        <TableCell>
          <div className="flex flex-wrap justify-end gap-2">
            {counts.failed > 0 ? (
              <BatchRelaunchButton
                label="Relancer les échecs"
                count={counts.failed}
                title={`Relancer les ${counts.failed} échecs de ${queue.name}`}
                description="Chaque job en échec repart avec ses tentatives remises à zéro, sauf process-activity et import-activity, que « Retraiter » relance depuis l'onglet Échecs."
                confirmLabel="Relancer"
                pending={actions.retryFailed.isPending}
                onConfirm={() =>
                  actions.retryFailed.mutate(queue.name, {
                    onSuccess: ({ retried, refused }) =>
                      toast.success(`${retried} relancé(s)${refused > 0 ? `, ${refused} à retraiter depuis Échecs` : ""}`),
                    onError: failed("Relance impossible"),
                  })
                }
              />
            ) : null}
            {queue.isPaused ? (
              <Button
                size="sm"
                variant="outline"
                disabled={actions.resume.isPending}
                onClick={() =>
                  actions.resume.mutate(queue.name, {
                    onSuccess: () => toast.success(`File ${queue.name} reprise`),
                    onError: failed("Reprise impossible"),
                  })
                }
              >
                Reprendre
              </Button>
            ) : (
              <Button
                size="sm"
                variant="outline"
                disabled={actions.pause.isPending}
                onClick={() =>
                  actions.pause.mutate(queue.name, {
                    onSuccess: () => toast.success(`File ${queue.name} mise en pause`),
                    onError: failed("Pause impossible"),
                  })
                }
              >
                Mettre en pause
              </Button>
            )}
          </div>
        </TableCell>
      </TableRow>
    );
  }

  return (
    <div className="flex flex-col gap-8">
      <div className="rounded-md border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>File</TableHead>
              <TableHead>État</TableHead>
              <TableHead>Jobs</TableHead>
              <TableHead>Échecs</TableHead>
              <TableHead>Planificateurs</TableHead>
              <TableHead />
            </TableRow>
          </TableHeader>
          <TableBody>
            {isLoading ? (
              <TableRow>
                <TableCell colSpan={6} className="text-center text-muted-foreground">
                  Chargement…
                </TableCell>
              </TableRow>
            ) : (
              data?.items.map(row)
            )}
          </TableBody>
        </Table>
      </div>
      {selected ? <QueueJobsSection queue={selected} /> : null}
    </div>
  );
}
