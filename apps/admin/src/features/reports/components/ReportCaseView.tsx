"use client";

import type { AdminReport, AdminReportCaseDetail, AdminReportCopy } from "@repo/contracts";
import { Avatar, AvatarFallback, AvatarImage } from "@repo/ui/components/avatar";
import { Badge } from "@repo/ui/components/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@repo/ui/components/card";
import { Skeleton } from "@repo/ui/components/skeleton";
import Link from "next/link";
import { SanctionAction } from "@/components/SanctionAction";
import { CloseCaseAction } from "@/features/reports/components/CloseCaseAction";
import { ReportCaseActions } from "@/features/reports/components/ReportCaseActions";
import { useReportCaseActions } from "@/features/reports/hooks/useReportCaseActions";
import { useReportCase } from "@/features/reports/hooks/useReportCases";
import {
  caseStatusLabels,
  caseStatusVariants,
  formatDateTime,
  reportReasonLabels,
  reportTargetLabels,
} from "@/features/reports/lib/labels";

type Actions = ReturnType<typeof useReportCaseActions>;

function PersonLink({ person }: { person: { id: string; displayName: string | null } | null }) {
  if (person === null || person.displayName === null) {
    return <span className="text-muted-foreground">Compte supprimé</span>;
  }
  return (
    <Link href={`/users/${person.id}`} className="underline-offset-4 hover:underline">
      {person.displayName || person.id.slice(0, 8)}
    </Link>
  );
}

/** The target as it is now (ADR-038 §10); Media removable as a Sanction while the case is open. */
function CurrentContent({ detail, actions, open }: { detail: AdminReportCaseDetail; actions: Actions; open: boolean }) {
  const { current } = detail;
  if (current === null) {
    return <p className="text-sm text-muted-foreground">Le contenu signalé n&apos;existe plus.</p>;
  }
  switch (current.kind) {
    case "comment":
      return (
        <div className="flex flex-col gap-2 text-sm">
          <p className="whitespace-pre-wrap">{current.body}</p>
          <span className="text-muted-foreground">
            {formatDateTime(current.createdAt)}
            {current.updatedAt ? " · modifié" : ""}
            {current.activity ? (
              <>
                {" · sous "}
                <Link href={`/activities/${current.activity.id}`} className="underline-offset-4 hover:underline">
                  {current.activity.title}
                </Link>
              </>
            ) : null}
          </span>
        </div>
      );
    case "activity":
      return (
        <div className="flex flex-col gap-3 text-sm">
          <p className="font-medium">{current.title}</p>
          {current.description ? <p className="whitespace-pre-wrap">{current.description}</p> : null}
          <Link href={`/activities/${detail.targetId}`} className="underline underline-offset-4">
            Voir l&apos;Activité
          </Link>
          {current.media.length > 0 ? (
            <ul className="grid grid-cols-2 gap-4 sm:grid-cols-4">
              {current.media.map((media, index) => (
                <li key={media.id} className="flex flex-col gap-2">
                  <a href={media.url} target="_blank" rel="noreferrer">
                    {/* eslint-disable-next-line @next/next/no-img-element -- pre-signed bucket URL, not optimisable */}
                    <img
                      src={media.thumbUrl}
                      alt={`Média ${index + 1} (${media.kind === "video" ? "vidéo" : "photo"})`}
                      className="aspect-square w-full rounded-md object-cover"
                    />
                  </a>
                  {open ? (
                    <SanctionAction
                      trigger={{ label: "Retirer", ariaLabel: `Retirer le Média ${index + 1}` }}
                      title="Retirer le Média"
                      summary={<>Le Média {index + 1} de l&apos;Activité « {current.title} » sera supprimé.</>}
                      confirmLabel="Retirer le Média"
                      successMessage="Média retiré"
                      run={(reason) =>
                        actions.removeMedia.mutateAsync({ activityId: detail.targetId, mediaId: media.id, reason })
                      }
                    />
                  ) : null}
                </li>
              ))}
            </ul>
          ) : (
            <p className="text-muted-foreground">Aucun Média.</p>
          )}
        </div>
      );
    case "athlete":
      return (
        <div className="flex items-start gap-3 text-sm">
          <Avatar className="size-12">
            {current.avatarUrl ? <AvatarImage src={current.avatarUrl} alt="" /> : null}
            <AvatarFallback>{current.displayName.slice(0, 1)}</AvatarFallback>
          </Avatar>
          <div className="flex flex-col gap-1">
            <Link href={`/users/${detail.targetId}`} className="font-medium underline-offset-4 hover:underline">
              {current.displayName}
            </Link>
            <p className="whitespace-pre-wrap text-muted-foreground">{current.bio ?? "Pas de bio."}</p>
          </div>
        </div>
      );
  }
}

/** A Report's copy, as it was sent. */
function CopyText({ copy }: { copy: AdminReportCopy }) {
  switch (copy.kind) {
    case "comment":
      return <p className="whitespace-pre-wrap">{copy.body}</p>;
    case "activity":
      return (
        <div className="flex flex-col gap-1">
          <p className="font-medium">{copy.title}</p>
          {copy.description ? <p className="whitespace-pre-wrap">{copy.description}</p> : null}
          <p className="text-muted-foreground">{copy.mediaCount} Média(s)</p>
        </div>
      );
    case "athlete":
      return (
        <div className="flex flex-col gap-1">
          <p className="font-medium">{copy.name}</p>
          <p className="whitespace-pre-wrap">{copy.bio ?? "Pas de bio."}</p>
          <p className="text-muted-foreground">{copy.hadAvatar ? "Avec une photo" : "Sans photo"}</p>
        </div>
      );
  }
}

function ReportItem({ report }: { report: AdminReport }) {
  return (
    <li className="flex flex-col gap-2 py-3 text-sm">
      <span className="text-muted-foreground">
        <PersonLink person={report.reporter} /> · {reportReasonLabels[report.reason]} · {formatDateTime(report.createdAt)}
      </span>
      {report.note ? <p className="whitespace-pre-wrap">{report.note}</p> : null}
      {report.copy && report.changedSince ? (
        <div className="rounded-md border border-dashed p-3">
          <Badge variant="outline" className="mb-2">
            modifié depuis le signalement
          </Badge>
          <CopyText copy={report.copy} />
        </div>
      ) : null}
    </li>
  );
}

/**
 * A case of the moderation queue (ADR-038 §10): the target now, beside the copies that differ; the
 * Reports; the author; then, while open, the Sanctions the target offers and « Clore ». A closed
 * case shows its outcome, who closed it (« Système » for an automatic close), and its note.
 */
export function ReportCaseView({ caseId }: { caseId: string }) {
  const { data: detail, isLoading, error } = useReportCase(caseId);
  const actions = useReportCaseActions(caseId);

  if (isLoading) {
    return <Skeleton className="h-64 w-full" />;
  }
  if (error || !detail) {
    return <p className="text-sm text-destructive">{error?.message ?? "Dossier introuvable."}</p>;
  }
  const open = detail.status === "open";
  const { author } = detail;

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center gap-2">
        <Badge variant="outline">{reportTargetLabels[detail.targetType]}</Badge>
        <Badge variant={caseStatusVariants[detail.status]}>{caseStatusLabels[detail.status]}</Badge>
        <span className="text-sm text-muted-foreground">Ouvert le {formatDateTime(detail.openedAt)}</span>
      </div>
      {!open && detail.closedAt ? (
        <Card>
          <CardHeader>
            <CardTitle>Clôture</CardTitle>
          </CardHeader>
          <CardContent className="flex flex-col gap-1 text-sm">
            <span>
              Clos le {formatDateTime(detail.closedAt)} par{" "}
              {detail.closedBy ? <PersonLink person={detail.closedBy} /> : "Système"}
            </span>
            {detail.closeNote ? <p className="whitespace-pre-wrap">{detail.closeNote}</p> : null}
          </CardContent>
        </Card>
      ) : null}
      <Card>
        <CardHeader>
          <CardTitle>Contenu actuel</CardTitle>
        </CardHeader>
        <CardContent>
          <CurrentContent detail={detail} actions={actions} open={open} />
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle>Signalements ({detail.reports.length})</CardTitle>
        </CardHeader>
        <CardContent>
          <ul className="flex flex-col divide-y">
            {detail.reports.map((report) => (
              <ReportItem key={report.id} report={report} />
            ))}
          </ul>
        </CardContent>
      </Card>
      <section aria-labelledby="report-author">
        <Card>
          <CardHeader>
            <CardTitle id="report-author">Auteur</CardTitle>
          </CardHeader>
          <CardContent className="flex flex-col gap-1 text-sm">
            <span className="flex items-center gap-2">
              <PersonLink person={author} />
              {author.banned ? <Badge variant="destructive">Banni</Badge> : null}
              {author.role === "admin" ? <Badge variant="secondary">Administrateur</Badge> : null}
            </span>
            <span className="text-muted-foreground">
              {author.reportsReceived} signalements reçus · {author.pastSanctions} Sanctions passées
            </span>
          </CardContent>
        </Card>
      </section>
      {open ? (
        <div className="flex flex-wrap items-center justify-between gap-2">
          <ReportCaseActions detail={detail} actions={actions} />
          <CloseCaseAction canResolve={detail.canResolve} reportCount={detail.reports.length} actions={actions} />
        </div>
      ) : null}
    </div>
  );
}
