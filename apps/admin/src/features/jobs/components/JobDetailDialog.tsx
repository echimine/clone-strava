"use client";

import { Button } from "@repo/ui/components/button";
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@repo/ui/components/collapsible";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@repo/ui/components/dialog";
import { Skeleton } from "@repo/ui/components/skeleton";
import Link from "next/link";
import { useJob } from "@/features/jobs/hooks/useQueues";
import { formatDateTime } from "@/features/jobs/lib/labels";

/**
 * A job's detail (ADR-038 §14), read-only: name, id, queue, reason, folded stack traces,
 * attempts, dates, and its data, with links to the Activity and athlete it names. No editing.
 */
export function JobDetailDialog({
  queue,
  jobId,
  onClose,
}: {
  queue: string;
  jobId: string | undefined;
  onClose: () => void;
}) {
  const { data: job, isLoading } = useJob(queue, jobId);

  return (
    <Dialog open={jobId !== undefined} onOpenChange={(open) => (open ? undefined : onClose())}>
      <DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-2xl">
        <DialogHeader>
          <DialogTitle className="font-mono">{job?.name ?? "Job"}</DialogTitle>
          <DialogDescription className="break-all font-mono text-xs">
            {queue} / {jobId}
          </DialogDescription>
        </DialogHeader>
        {isLoading || !job ? (
          <Skeleton className="h-40 w-full" />
        ) : (
          <div className="flex flex-col gap-4 text-sm">
            <dl className="grid grid-cols-[max-content_1fr] gap-x-4 gap-y-1">
              <dt className="text-muted-foreground">État</dt>
              <dd>{job.state}</dd>
              <dt className="text-muted-foreground">Raison</dt>
              <dd>{job.failedReason ?? "—"}</dd>
              <dt className="text-muted-foreground">Tentatives</dt>
              <dd>
                {job.attemptsMade}/{job.maxAttempts}
              </dd>
              <dt className="text-muted-foreground">Créé le</dt>
              <dd>{formatDateTime(job.createdAt)}</dd>
              <dt className="text-muted-foreground">Démarré le</dt>
              <dd>{formatDateTime(job.processedAt)}</dd>
              <dt className="text-muted-foreground">Terminé le</dt>
              <dd>{formatDateTime(job.finishedAt)}</dd>
            </dl>
            {job.activityId || job.userId ? (
              <div className="flex gap-2">
                {job.activityId ? (
                  <Button asChild size="sm" variant="outline">
                    <Link href={`/activities/${job.activityId}`}>Voir l&apos;Activité</Link>
                  </Button>
                ) : null}
                {job.userId ? (
                  <Button asChild size="sm" variant="outline">
                    <Link href={`/users/${job.userId}`}>Voir l&apos;athlète</Link>
                  </Button>
                ) : null}
              </div>
            ) : null}
            {job.stacktrace.length > 0 ? (
              <Collapsible>
                <CollapsibleTrigger asChild>
                  <Button size="sm" variant="ghost" className="px-0">
                    Pile d&apos;appels
                  </Button>
                </CollapsibleTrigger>
                <CollapsibleContent>
                  <pre className="max-h-64 overflow-auto rounded-md bg-muted p-3 text-xs">
                    {job.stacktrace.join("\n\n")}
                  </pre>
                </CollapsibleContent>
              </Collapsible>
            ) : null}
            <div className="flex flex-col gap-1">
              <span className="text-muted-foreground">Données (lecture seule)</span>
              <pre className="max-h-64 overflow-auto rounded-md bg-muted p-3 text-xs">
                {JSON.stringify(job.data, null, 2)}
              </pre>
            </div>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
