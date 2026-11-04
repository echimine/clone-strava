"use client";

import { banDurationSchema, type AdminReportCaseDetail, type BanDuration } from "@repo/contracts";
import { Label } from "@repo/ui/components/label";
import { NativeSelect, NativeSelectOption } from "@repo/ui/components/native-select";
import { useState } from "react";
import { SanctionAction } from "@/components/SanctionAction";
import type { useReportCaseActions } from "@/features/reports/hooks/useReportCaseActions";
import { banDurationLabels, banEndLabel } from "@/features/reports/lib/labels";

type Actions = ReturnType<typeof useReportCaseActions>;

/** « Bannir l'auteur » (ADR-038 §6, §10), with the Ban's duration. */
function BanAuthorAction({ authorId, name, actions }: { authorId: string; name: string; actions: Actions }) {
  const [duration, setDuration] = useState<BanDuration>("24h");
  const [openedAt, setOpenedAt] = useState(() => new Date());

  return (
    <SanctionAction
      trigger={{ label: "Bannir l'auteur", variant: "destructive" }}
      title="Bannir l'auteur"
      summary={
        <>
          {name} sera banni <strong>{banEndLabel(duration, openedAt)}</strong>. Ses sessions sont fermées et ce
          qu&apos;il a partagé est masqué jusqu&apos;à la fin du Ban.
        </>
      }
      confirmLabel="Bannir"
      successMessage="Auteur banni"
      onOpenChange={(open) => {
        if (open) {
          setDuration("24h");
          setOpenedAt(new Date());
        }
      }}
      run={(reason) => actions.ban.mutateAsync({ userId: authorId, duration, reason })}
    >
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="report-ban-duration">Durée</Label>
        <NativeSelect
          id="report-ban-duration"
          value={duration}
          onChange={(event) => setDuration(banDurationSchema.parse(event.target.value))}
        >
          {banDurationSchema.options.map((option) => (
            <NativeSelectOption key={option} value={option}>
              {banDurationLabels[option]}
            </NativeSelectOption>
          ))}
        </NativeSelect>
      </div>
    </SanctionAction>
  );
}

/**
 * The Sanctions a case offers for its target (ADR-038 §10), each through the shared Sanction
 * dialog and the endpoint of its own screen: a comment → remove it; an Activity → delete it or
 * reset its text (its Media are removed from their thumbnails); an athlete → reset name, bio or
 * Avatar; every target → ban the author, unless they are an Administrator or gone.
 */
export function ReportCaseActions({ detail, actions }: { detail: AdminReportCaseDetail; actions: Actions }) {
  const { current, author, targetId } = detail;
  const name = author.displayName || "l'athlète";
  const canBan = author.role === "user";

  return (
    <div className="flex flex-wrap gap-2">
      {current?.kind === "comment" ? (
        <SanctionAction
          trigger={{ label: "Retirer le commentaire", variant: "destructive" }}
          title="Retirer le commentaire"
          summary={<>Le commentaire de {name} sera retiré. Le dossier se clôt de lui-même.</>}
          confirmLabel="Retirer le commentaire"
          successMessage="Commentaire retiré"
          run={(reason) => actions.removeComment.mutateAsync({ commentId: targetId, reason })}
        />
      ) : null}
      {current?.kind === "activity" ? (
        <>
          <SanctionAction
            trigger={{ label: "Réinitialiser titre et description" }}
            title="Réinitialiser titre et description"
            summary={
              <>Le titre de l&apos;Activité « {current.title} » reprendra sa valeur par défaut et sa description sera vidée.</>
            }
            confirmLabel="Réinitialiser"
            successMessage="Titre et description réinitialisés"
            run={(reason) => actions.resetText.mutateAsync({ activityId: targetId, reason })}
          />
          <SanctionAction
            trigger={{ label: "Supprimer l'Activité", variant: "destructive" }}
            title="Supprimer l'Activité"
            summary={
              <>
                L&apos;Activité « {current.title} » de {name} sera supprimée définitivement, avec sa trace, ses Médias,
                ses commentaires et ses kudos. Le dossier se clôt de lui-même.
              </>
            }
            confirmLabel="Supprimer"
            successMessage="Activité supprimée"
            run={(reason) => actions.deleteActivity.mutateAsync({ activityId: targetId, reason })}
          />
        </>
      ) : null}
      {current?.kind === "athlete" ? (
        <>
          <SanctionAction
            trigger={{ label: "Réinitialiser le nom" }}
            title="Réinitialiser le nom"
            summary={<>Le nom de {name} deviendra « Athlète » (prénom), sans nom de famille.</>}
            confirmLabel="Réinitialiser"
            successMessage="Nom réinitialisé"
            run={(reason) => actions.resetProfile.mutateAsync({ userId: targetId, reset: "reset-name", reason })}
          />
          <SanctionAction
            trigger={{ label: "Vider la bio" }}
            title="Vider la bio"
            summary={<>La bio de {name} sera vidée.</>}
            confirmLabel="Vider"
            successMessage="Bio vidée"
            run={(reason) => actions.resetProfile.mutateAsync({ userId: targetId, reset: "reset-bio", reason })}
          />
          <SanctionAction
            trigger={{ label: "Retirer la photo" }}
            title="Retirer la photo de profil"
            summary={<>La photo de profil de {name} sera supprimée ; ses initiales s&apos;afficheront.</>}
            confirmLabel="Retirer"
            successMessage="Photo retirée"
            run={(reason) => actions.resetProfile.mutateAsync({ userId: targetId, reset: "reset-avatar", reason })}
          />
        </>
      ) : null}
      {canBan ? <BanAuthorAction authorId={author.id} name={name} actions={actions} /> : null}
    </div>
  );
}
