"use client";

import { banDurationSchema, type AdminUserDetail, type BanDuration } from "@repo/contracts";
import { Input } from "@repo/ui/components/input";
import { Label } from "@repo/ui/components/label";
import { NativeSelect, NativeSelectOption } from "@repo/ui/components/native-select";
import { useState } from "react";
import { SanctionAction } from "@/components/SanctionAction";
import type { useUserActions } from "@/features/users/hooks/useUserActions";
import { banDurationLabels, banEndLabel } from "@/features/users/lib/labels";

type Actions = ReturnType<typeof useUserActions>;

function BanAction({ user, actions, name }: { user: AdminUserDetail; actions: Actions; name: string }) {
  const [duration, setDuration] = useState<BanDuration>("24h");
  const [openedAt, setOpenedAt] = useState(() => new Date());

  return (
    <SanctionAction
      trigger={{ label: user.ban ? "Bannir à nouveau" : "Bannir", variant: "destructive" }}
      title="Bannir l'athlète"
      summary={
        <>
          {name} sera banni <strong>{banEndLabel(duration, openedAt)}</strong>. Ses sessions sont fermées et ce
          qu&apos;il a partagé est masqué jusqu&apos;à la fin du Ban.
          {user.ban ? " Ce Ban remplace le Ban en cours." : null}
        </>
      }
      confirmLabel="Bannir"
      successMessage="Athlète banni"
      onOpenChange={(open) => {
        if (open) {
          setDuration("24h");
          setOpenedAt(new Date());
        }
      }}
      run={(reason) => actions.ban.mutateAsync({ duration, reason })}
    >
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="ban-duration">Durée</Label>
        <NativeSelect
          id="ban-duration"
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
      {user.premium.billedByAppStore ? (
        <p role="note" className="text-sm text-amber-700 dark:text-amber-400">
          Cet athlète a un abonnement Premium payant : Apple continue de le facturer pendant le Ban.
        </p>
      ) : null}
    </SanctionAction>
  );
}

function RoleAction({ user, actions, name }: { user: AdminUserDetail; actions: Actions; name: string }) {
  const [typedEmail, setTypedEmail] = useState("");
  const promote = user.role !== "admin";

  return (
    <SanctionAction
      trigger={{ label: promote ? "Nommer administrateur" : "Retirer le rôle administrateur" }}
      title={promote ? "Nommer administrateur" : "Retirer le rôle administrateur"}
      summary={
        promote ? (
          <>
            {name} aura accès au backoffice. Il configurera sa double authentification à sa première connexion.
          </>
        ) : (
          <>{name} n&apos;aura plus accès au backoffice.</>
        )
      }
      confirmLabel={promote ? "Nommer" : "Retirer le rôle"}
      successMessage={promote ? "Rôle administrateur attribué" : "Rôle administrateur retiré"}
      reasonRequired={false}
      canConfirm={typedEmail.trim().toLowerCase() === user.email.toLowerCase()}
      onOpenChange={() => setTypedEmail("")}
      run={(reason) => actions.setRole.mutateAsync({ role: promote ? "admin" : "user", reason })}
    >
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="role-email">Retapez l&apos;e-mail du compte pour confirmer</Label>
        <Input
          id="role-email"
          type="email"
          autoComplete="off"
          placeholder={user.email}
          value={typedEmail}
          onChange={(event) => setTypedEmail(event.target.value)}
        />
      </div>
    </SanctionAction>
  );
}

/**
 * The account's actions on the user sheet (ADR-038 §5): the Sanctions (Ban, unban, sign-out,
 * resets), each with the shared Sanction dialog, and the admin role. An Administrator is never
 * banned: no Ban button on their sheet (the API answers `409` anyway).
 */
export function UserActions({ user, actions }: { user: AdminUserDetail; actions: Actions }) {
  const name = user.athlete.displayName || user.email;
  return (
    <div className="flex flex-wrap gap-2">
      {user.role !== "admin" ? <BanAction user={user} actions={actions} name={name} /> : null}
      {user.ban ? (
        <SanctionAction
          trigger={{ label: "Lever le Ban" }}
          title="Lever le Ban"
          summary={<>{name} pourra se reconnecter immédiatement et ce qu&apos;il a partagé redeviendra visible.</>}
          confirmLabel="Lever le Ban"
          successMessage="Ban levé"
          run={(reason) => actions.unban.mutateAsync(reason)}
        />
      ) : null}
      <SanctionAction
        trigger={{ label: "Déconnecter partout" }}
        title="Déconnecter partout"
        summary={<>Toutes les sessions de {name} seront fermées. Il pourra se reconnecter aussitôt.</>}
        confirmLabel="Déconnecter"
        successMessage="Sessions fermées"
        run={(reason) => actions.signOut.mutateAsync(reason)}
      />
      <SanctionAction
        trigger={{ label: "Réinitialiser le nom" }}
        title="Réinitialiser le nom"
        summary={<>Le nom de {name} deviendra « Athlète » (prénom), sans nom de famille.</>}
        confirmLabel="Réinitialiser"
        successMessage="Nom réinitialisé"
        run={(reason) => actions.reset.mutateAsync({ reset: "reset-name", reason })}
      />
      <SanctionAction
        trigger={{ label: "Vider la bio" }}
        title="Vider la bio"
        summary={<>La bio de {name} sera vidée.</>}
        confirmLabel="Vider"
        successMessage="Bio vidée"
        run={(reason) => actions.reset.mutateAsync({ reset: "reset-bio", reason })}
      />
      <SanctionAction
        trigger={{ label: "Retirer la photo" }}
        title="Retirer la photo de profil"
        summary={<>La photo de profil de {name} sera supprimée ; ses initiales s&apos;afficheront.</>}
        confirmLabel="Retirer"
        successMessage="Photo retirée"
        run={(reason) => actions.reset.mutateAsync({ reset: "reset-avatar", reason })}
      />
      <RoleAction user={user} actions={actions} name={name} />
    </div>
  );
}
