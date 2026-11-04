"use client";

import {
  promotionalPremiumDurationSchema,
  type AdminUserPremium,
  type PromotionalPremiumDuration,
} from "@repo/contracts";
import { Badge } from "@repo/ui/components/badge";
import { Button } from "@repo/ui/components/button";
import { Label } from "@repo/ui/components/label";
import { NativeSelect, NativeSelectOption } from "@repo/ui/components/native-select";
import { Skeleton } from "@repo/ui/components/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@repo/ui/components/table";
import { useState, type ReactNode } from "react";
import { toast } from "sonner";
import { SanctionAction } from "@/components/SanctionAction";
import { usePremium, usePremiumActions } from "@/features/premium/hooks/usePremium";
import {
  eventSourceLabel,
  eventTypeLabel,
  formatDate,
  formatDateTime,
  periodTypeLabels,
  storeLabels,
} from "@/features/premium/lib/labels";
import { premiumStateLabels, promotionalDurationLabels } from "@/lib/premium-labels";

const NOT_CONFIGURED = "RevenueCat non configuré";
/** Premium actions are not Sanctions: the reason stays in the Journal, the athlete gets no e-mail. */
const REASON_NOTICE = "Ce motif reste dans le Journal ; l'athlète ne reçoit aucun e-mail.";

type Actions = ReturnType<typeof usePremiumActions>;

function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="flex flex-col">
      <dt className="text-muted-foreground">{label}</dt>
      <dd>{children}</dd>
    </div>
  );
}

/** « Résilié jusqu'au 12/12/2026 », « Premium offert jusqu'au … », « Expiré le … ». */
function stateText(premium: AdminUserPremium): string {
  const label = premiumStateLabels[premium.state];
  const end = premium.detail?.gracePeriodExpiresAt ?? premium.detail?.expiresAt ?? null;
  if (!end) {
    return label;
  }
  switch (premium.state) {
    case "cancelled":
    case "promotional":
    case "grace_period":
      return `${label} jusqu'au ${formatDate(end)}`;
    case "expired":
      return `${label} le ${formatDate(end)}`;
    default:
      return label;
  }
}

function Detail({ premium }: { premium: AdminUserPremium }) {
  const detail = premium.detail;
  if (!detail) {
    return null;
  }
  return (
    <dl className="grid grid-cols-2 gap-4 text-sm md:grid-cols-4">
      <Field label="Produit">{detail.productId ?? "—"}</Field>
      <Field label="Magasin">{detail.store ? storeLabels[detail.store] : "—"}</Field>
      <Field label="Période">{detail.periodType ? periodTypeLabels[detail.periodType] : "—"}</Field>
      <Field label="Achat">{formatDate(detail.purchasedAt)}</Field>
      <Field label={detail.willRenew ? "Renouvellement" : "Fin"}>{formatDate(detail.expiresAt)}</Field>
      <Field label="Renouvellement automatique">{detail.willRenew ? "Oui" : "Non"}</Field>
      <Field label="Désabonnement détecté">{formatDate(detail.unsubscribeDetectedAt)}</Field>
      {detail.billingIssueDetectedAt ? (
        <Field label="Problème de paiement détecté">{formatDate(detail.billingIssueDetectedAt)}</Field>
      ) : null}
      {detail.gracePeriodExpiresAt ? (
        <Field label="Fin de la période de grâce">{formatDate(detail.gracePeriodExpiresAt)}</Field>
      ) : null}
      <Field label="Dernière synchro">{formatDateTime(detail.syncedAt)}</Field>
    </dl>
  );
}

function History({ premium }: { premium: AdminUserPremium }) {
  if (premium.history.length === 0) {
    return <p className="text-sm text-muted-foreground">Aucun événement RevenueCat.</p>;
  }
  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Événement</TableHead>
          <TableHead>Date</TableHead>
          <TableHead>Produit</TableHead>
          <TableHead>Source</TableHead>
          <TableHead>Fin</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {premium.history.map((event) => (
          <TableRow key={event.id}>
            <TableCell>
              {eventTypeLabel(event.type)}
              {event.sandbox ? (
                <Badge variant="outline" className="ml-2">
                  Sandbox
                </Badge>
              ) : null}
            </TableCell>
            <TableCell>{formatDateTime(event.occurredAt)}</TableCell>
            <TableCell>{event.productId ?? "—"}</TableCell>
            <TableCell>{eventSourceLabel(event.store, event.periodType)}</TableCell>
            <TableCell>{formatDate(event.expiresAt)}</TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}

function GrantAction({ premium, actions }: { premium: AdminUserPremium; actions: Actions }) {
  const [duration, setDuration] = useState<PromotionalPremiumDuration>("1m");
  const replaces = premium.state === "promotional";
  const billed = premium.detail?.store === "app_store" && premium.state !== "expired";
  return (
    <SanctionAction
      trigger={{ label: replaces ? "Offrir de nouveau" : "Offrir le Premium" }}
      title="Offrir le Premium"
      summary={
        <>
          L&apos;athlète sera Premium pendant <strong>{promotionalDurationLabels[duration]}</strong> à partir
          d&apos;aujourd&apos;hui, sans achat.
          {replaces ? " Cette offre remplace la date de fin du Premium offert en cours." : null}
          {billed ? " Son abonnement App Store n'est pas touché." : null}
        </>
      }
      confirmLabel="Offrir"
      successMessage="Premium offert"
      reasonNotice={REASON_NOTICE}
      disabled={!premium.configured}
      disabledReason={NOT_CONFIGURED}
      onOpenChange={(open) => {
        if (open) {
          setDuration("1m");
        }
      }}
      run={(reason) => actions.grant.mutateAsync({ duration, reason })}
    >
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="premium-duration">Durée</Label>
        <NativeSelect
          id="premium-duration"
          value={duration}
          onChange={(event) => setDuration(promotionalPremiumDurationSchema.parse(event.target.value))}
        >
          {promotionalPremiumDurationSchema.options.map((option) => (
            <NativeSelectOption key={option} value={option}>
              {promotionalDurationLabels[option]}
            </NativeSelectOption>
          ))}
        </NativeSelect>
      </div>
    </SanctionAction>
  );
}

function PremiumActions({ premium, actions }: { premium: AdminUserPremium; actions: Actions }) {
  async function resync() {
    try {
      const { queued } = await actions.sync.mutateAsync();
      toast.success(queued ? "Resynchronisation lancée" : "Une resynchronisation est déjà en attente");
    } catch (caught: unknown) {
      toast.error(caught instanceof Error ? caught.message : "Une erreur est survenue");
    }
  }

  return (
    <div className="flex flex-wrap items-center gap-2">
      <Button
        variant="outline"
        size="sm"
        disabled={!premium.configured || actions.sync.isPending}
        title={premium.configured ? undefined : NOT_CONFIGURED}
        onClick={() => void resync()}
      >
        Resynchroniser
      </Button>
      <GrantAction premium={premium} actions={actions} />
      {premium.state === "promotional" ? (
        <SanctionAction
          trigger={{ label: "Retirer le Premium offert", variant: "destructive" }}
          title="Retirer le Premium offert"
          summary={<>Le Premium offert prend fin immédiatement. Un abonnement App Store n&apos;est jamais touché.</>}
          confirmLabel="Retirer"
          successMessage="Premium offert retiré"
          reasonNotice={REASON_NOTICE}
          disabled={!premium.configured}
          disabledReason={NOT_CONFIGURED}
          run={(reason) => actions.revoke.mutateAsync(reason)}
        />
      ) : null}
      {premium.configured ? null : <p className="text-sm text-muted-foreground">{NOT_CONFIGURED}</p>}
    </div>
  );
}

/**
 * The user sheet's section 6 « Premium » (ADR-038 §12): the state, the detail and the history of
 * RevenueCat events, read in our tables only, a link to the customer in RevenueCat, and
 * « Resynchroniser », « Offrir le Premium », « Retirer le Premium offert » (disabled without
 * RevenueCat). Composed into `UserSheet`'s `premium` slot by the page.
 */
export function PremiumSection({ userId }: { userId: string }) {
  const { data: premium, isLoading } = usePremium(userId);
  const actions = usePremiumActions(userId);

  if (isLoading) {
    return <Skeleton className="h-24 w-full" />;
  }
  if (!premium) {
    return (
      <p role="alert" className="text-sm text-destructive">
        Impossible de charger le Premium.
      </p>
    );
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center gap-2">
        <Badge variant={premium.state === "never" || premium.state === "expired" ? "secondary" : "default"}>
          {stateText(premium)}
        </Badge>
        {premium.detail?.sandbox ? <Badge variant="outline">Sandbox</Badge> : null}
        {premium.revenueCatUrl ? (
          <a
            href={premium.revenueCatUrl}
            target="_blank"
            rel="noreferrer"
            className="text-sm underline underline-offset-4"
          >
            Voir dans RevenueCat
          </a>
        ) : null}
      </div>
      <Detail premium={premium} />
      <PremiumActions premium={premium} actions={actions} />
      <h3 className="text-sm font-medium">Historique RevenueCat</h3>
      <History premium={premium} />
    </div>
  );
}
