"use client";

import type { AdminActivityDetail } from "@repo/contracts";
import { Card, CardContent, CardHeader, CardTitle } from "@repo/ui/components/card";
import Link from "next/link";
import { SanctionAction } from "@/features/activities/components/SanctionAction";
import type { useActivityActions } from "@/features/activities/hooks/useActivityActions";
import {
  formatDateTime,
  formatDuration,
  importStatusLabels,
} from "@/features/activities/lib/labels";

type Actions = ReturnType<typeof useActivityActions>;

function AthleteLink({ athlete }: { athlete: AdminActivityDetail["athlete"] }) {
  return (
    <Link href={`/users/${athlete.id}`} className="underline-offset-4 hover:underline">
      {athlete.displayName || athlete.id.slice(0, 8)}
    </Link>
  );
}

/** The Activity's Media as thumbnails (ADR-037 pre-signed URLs), each removable as a Sanction. */
export function ActivityMediaSection({ activity, actions }: { activity: AdminActivityDetail; actions: Actions }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Médias ({activity.media.length})</CardTitle>
      </CardHeader>
      <CardContent>
        {activity.media.length === 0 ? (
          <p className="text-sm text-muted-foreground">Aucun Média.</p>
        ) : (
          <ul className="grid grid-cols-2 gap-4 sm:grid-cols-4">
            {activity.media.map((media, index) => (
              <li key={media.id} className="flex flex-col gap-2">
                <a href={media.url} target="_blank" rel="noreferrer">
                  {/* eslint-disable-next-line @next/next/no-img-element -- pre-signed bucket URL, not optimisable */}
                  <img
                    src={media.thumbUrl}
                    alt={`Média ${index + 1} (${media.kind === "video" ? "vidéo" : "photo"})`}
                    className="aspect-square w-full rounded-md object-cover"
                  />
                </a>
                <SanctionAction
                  trigger={{ label: "Retirer", ariaLabel: `Retirer le Média ${index + 1}` }}
                  title="Retirer le Média"
                  summary={<>Le Média {index + 1} de l&apos;Activité « {activity.title} » sera supprimé.</>}
                  confirmLabel="Retirer le Média"
                  successMessage="Média retiré"
                  run={(reason) => actions.removeMedia.mutateAsync({ mediaId: media.id, reason })}
                />
              </li>
            ))}
          </ul>
        )}
      </CardContent>
    </Card>
  );
}

/** Comments not deleted, newest first, each removable as a Sanction (ADR-034 soft delete). */
export function ActivityCommentsSection({ activity, actions }: { activity: AdminActivityDetail; actions: Actions }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Commentaires ({activity.commentCount})</CardTitle>
      </CardHeader>
      <CardContent>
        {activity.comments.length === 0 ? (
          <p className="text-sm text-muted-foreground">Aucun commentaire.</p>
        ) : (
          <ul className="flex flex-col divide-y">
            {activity.comments.map((comment) => (
              <li key={comment.id} className="flex items-start justify-between gap-4 py-3">
                <div className="flex flex-col gap-1 text-sm">
                  <span className="text-muted-foreground">
                    <AthleteLink athlete={comment.author} /> · {formatDateTime(comment.createdAt)}
                    {comment.updatedAt ? " · modifié" : ""}
                  </span>
                  <p className="whitespace-pre-wrap">{comment.body}</p>
                </div>
                <SanctionAction
                  trigger={{ label: "Retirer" }}
                  title="Retirer le commentaire"
                  summary={
                    <>
                      Le commentaire de {comment.author.displayName || "l'athlète"} sur « {activity.title} » sera
                      retiré.
                    </>
                  }
                  confirmLabel="Retirer le commentaire"
                  successMessage="Commentaire retiré"
                  run={(reason) => actions.removeComment.mutateAsync({ commentId: comment.id, reason })}
                />
              </li>
            ))}
          </ul>
        )}
      </CardContent>
    </Card>
  );
}

/** Kudos (read-only, ADR-038 §11: no kudos removal), the linked import, and Segment efforts. */
export function ActivityExtrasSection({ activity }: { activity: AdminActivityDetail }) {
  return (
    <div className="grid gap-4 md:grid-cols-3">
      <Card>
        <CardHeader>
          <CardTitle>Kudos ({activity.kudosCount})</CardTitle>
        </CardHeader>
        <CardContent>
          {activity.kudos.length === 0 ? (
            <p className="text-sm text-muted-foreground">Aucun kudos.</p>
          ) : (
            <ul className="flex flex-col gap-1 text-sm">
              {activity.kudos.map((given) => (
                <li key={given.athlete.id}>
                  <AthleteLink athlete={given.athlete} />{" "}
                  <span className="text-muted-foreground">· {formatDateTime(given.createdAt)}</span>
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle>Import</CardTitle>
        </CardHeader>
        <CardContent className="text-sm">
          {activity.import ? (
            <p>
              {activity.import.fileName} · {activity.import.format.toUpperCase()} ·{" "}
              {importStatusLabels[activity.import.status]}
              {activity.import.error ? ` · ${activity.import.error}` : ""}
            </p>
          ) : (
            <p className="text-muted-foreground">Aucun import.</p>
          )}
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle>Efforts sur Segments</CardTitle>
        </CardHeader>
        <CardContent>
          {activity.efforts.length === 0 ? (
            <p className="text-sm text-muted-foreground">Aucun effort.</p>
          ) : (
            <ul className="flex flex-col gap-1 text-sm">
              {activity.efforts.map((effort) => (
                <li key={effort.id}>
                  <span>{effort.segmentName}</span>{" "}
                  <span className="text-muted-foreground">
                    · {formatDuration(effort.elapsedTimeS)}
                    {effort.rank === null ? "" : ` · rang ${effort.rank}`}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
