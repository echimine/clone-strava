"use client";

import type { AdminActivityDetail } from "@repo/contracts";
import { Button } from "@repo/ui/components/button";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { SanctionAction } from "@/components/SanctionAction";
import type { useActivityActions } from "@/features/activities/hooks/useActivityActions";
import { formatDateTime } from "@/features/activities/lib/labels";

/**
 * The Activity's own actions (ADR-038 §11): « Retraiter » on a failed Activity only (not a
 * Sanction), then the Sanctions « Réinitialiser titre et description » and « Supprimer
 * l'Activité ». Deleting goes back to the list.
 */
export function ActivityActions({
  activity,
  actions,
}: {
  activity: AdminActivityDetail;
  actions: ReturnType<typeof useActivityActions>;
}) {
  const router = useRouter();
  const named = (
    <>
      « {activity.title} » de {activity.athlete.displayName || "l'athlète"} ({formatDateTime(activity.startedAt)})
    </>
  );

  return (
    <div className="flex flex-wrap gap-2">
      {activity.processingStatus === "failed" ? (
        <Button
          size="sm"
          disabled={actions.reprocess.isPending}
          onClick={() =>
            actions.reprocess.mutate(undefined, {
              onSuccess: () => toast.success("Activité renvoyée en traitement"),
              onError: (error) => toast.error(error.message),
            })
          }
        >
          Retraiter
        </Button>
      ) : null}
      <SanctionAction
        trigger={{ label: "Réinitialiser titre et description" }}
        title="Réinitialiser titre et description"
        summary={<>Le titre de l&apos;Activité {named} reprendra sa valeur par défaut et sa description sera vidée.</>}
        confirmLabel="Réinitialiser"
        successMessage="Titre et description réinitialisés"
        run={(reason) => actions.resetText.mutateAsync(reason)}
      />
      <SanctionAction
        trigger={{ label: "Supprimer l'Activité", variant: "destructive" }}
        title="Supprimer l'Activité"
        summary={
          <>
            L&apos;Activité {named} sera supprimée définitivement, avec sa trace, ses Médias, ses commentaires et ses
            kudos.
          </>
        }
        confirmLabel="Supprimer"
        successMessage="Activité supprimée"
        run={(reason) => actions.deleteActivity.mutateAsync(reason)}
        onDone={() => router.push("/activities")}
      />
    </div>
  );
}
