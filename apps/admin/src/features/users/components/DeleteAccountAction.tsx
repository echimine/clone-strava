"use client";

import type { AdminUserDetail } from "@repo/contracts";
import { Input } from "@repo/ui/components/input";
import { Label } from "@repo/ui/components/label";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { SanctionAction } from "@/components/SanctionAction";
import type { useUserActions } from "@/features/users/hooks/useUserActions";

type Actions = ReturnType<typeof useUserActions>;

/** Ignores case, accents and surrounding spaces: the confirmation is about intent, not typing. */
function normalized(name: string): string {
  return name.normalize("NFD").replace(/\p{Diacritic}/gu, "").trim().toLowerCase();
}

/**
 * Sanction « Supprimer le compte » (ADR-038 §13): immediate and final, confirmed by typing the
 * athlete's name; the athlete receives « Votre compte Nervo a été supprimé » with the reason.
 * Never offered for an Administrator. Back to the users list once done.
 */
export function DeleteAccountAction({ user, actions, name }: { user: AdminUserDetail; actions: Actions; name: string }) {
  const router = useRouter();
  const [typedName, setTypedName] = useState("");

  return (
    <SanctionAction
      trigger={{ label: "Supprimer le compte", variant: "destructive" }}
      title="Supprimer le compte"
      summary={
        <>
          Le compte de {name} sera supprimé immédiatement, de façon définitive : profil, Activités et Médias,
          commentaires et kudos, abonnés et abonnements. Ses Signalements restent, sans auteur ni note.
        </>
      }
      confirmLabel="Supprimer définitivement"
      successMessage="Compte supprimé"
      canConfirm={typedName.trim() !== "" && normalized(typedName) === normalized(name)}
      onOpenChange={() => setTypedName("")}
      run={(reason) => actions.remove.mutateAsync(reason)}
      onDone={() => router.push("/users")}
    >
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="delete-account-name">Tapez le nom de l&apos;athlète pour confirmer</Label>
        <Input
          id="delete-account-name"
          autoComplete="off"
          placeholder={name}
          value={typedName}
          onChange={(event) => setTypedName(event.target.value)}
        />
      </div>
      {user.premium.billedByAppStore ? (
        <p role="note" className="text-sm text-amber-700 dark:text-amber-400">
          Cet athlète a un abonnement Premium payant : Apple continue de le facturer jusqu&apos;à ce qu&apos;il le
          résilie lui-même.
        </p>
      ) : null}
    </SanctionAction>
  );
}
