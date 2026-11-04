"use client";

import { ADMIN_REASON_MAX_LENGTH } from "@repo/contracts";
import { Button } from "@repo/ui/components/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@repo/ui/components/dialog";
import { Label } from "@repo/ui/components/label";
import { Textarea } from "@repo/ui/components/textarea";
import { useId, useState, type FormEvent } from "react";
import { toast } from "sonner";
import type { useReportCaseActions } from "@/features/reports/hooks/useReportCaseActions";

type Outcome = "resolve" | "dismiss";

/**
 * « Clore » (ADR-038 §10): « Sanctionné » or « Rejeter », with an optional note; every Report of
 * the case closes with it. « Sanctionné » needs a Sanction in the Journal since the opening, on the
 * target or its author: without one, only « Rejeter » can be chosen. Not a Sanction: nothing is
 * sent to anyone.
 */
export function CloseCaseAction({
  canResolve,
  reportCount,
  actions,
}: {
  canResolve: boolean;
  reportCount: number;
  actions: ReturnType<typeof useReportCaseActions>;
}) {
  const noteId = useId();
  const [open, setOpen] = useState(false);
  const [outcome, setOutcome] = useState<Outcome>("dismiss");
  const [note, setNote] = useState("");
  const [error, setError] = useState<string | null>(null);

  function changeOpen(next: boolean) {
    setOpen(next);
    if (next) {
      setOutcome(canResolve ? "resolve" : "dismiss");
      setNote("");
      setError(null);
    }
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    setError(null);
    try {
      await actions.close.mutateAsync({ outcome, note: note.trim() });
      toast.success(outcome === "resolve" ? "Dossier clos : sanctionné" : "Dossier rejeté");
      setOpen(false);
    } catch (caught: unknown) {
      setError(caught instanceof Error ? caught.message : "Une erreur est survenue");
    }
  }

  return (
    <>
      <Button size="sm" onClick={() => changeOpen(true)}>
        Clore
      </Button>
      <Dialog open={open} onOpenChange={changeOpen}>
        <DialogContent>
          <form onSubmit={(event) => void submit(event)} className="flex flex-col gap-4">
            <DialogHeader>
              <DialogTitle>Clore le dossier</DialogTitle>
              <DialogDescription>
                {reportCount > 1 ? `Les ${reportCount} signalements` : "Le signalement"} du dossier seront clos
                ensemble et leurs copies effacées. Ni le signaleur ni l&apos;auteur ne sont prévenus.
              </DialogDescription>
            </DialogHeader>
            <fieldset className="flex flex-col gap-2">
              <legend className="sr-only">Issue</legend>
              <label className="flex items-center gap-2 text-sm">
                <input
                  type="radio"
                  name="outcome"
                  value="resolve"
                  checked={outcome === "resolve"}
                  disabled={!canResolve}
                  onChange={() => setOutcome("resolve")}
                />
                Sanctionné
              </label>
              {canResolve ? null : (
                <p className="pl-6 text-xs text-muted-foreground">
                  Possible après une Sanction sur le contenu ou son auteur : aucune Sanction depuis l&apos;ouverture.
                </p>
              )}
              <label className="flex items-center gap-2 text-sm">
                <input
                  type="radio"
                  name="outcome"
                  value="dismiss"
                  checked={outcome === "dismiss"}
                  onChange={() => setOutcome("dismiss")}
                />
                Rejeter
              </label>
            </fieldset>
            <div className="flex flex-col gap-1.5">
              <Label htmlFor={noteId}>Note (facultative)</Label>
              <Textarea
                id={noteId}
                value={note}
                maxLength={ADMIN_REASON_MAX_LENGTH}
                onChange={(event) => setNote(event.target.value)}
              />
            </div>
            {error ? (
              <p role="alert" className="text-sm text-destructive">
                {error}
              </p>
            ) : null}
            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setOpen(false)}>
                Annuler
              </Button>
              <Button type="submit" disabled={actions.close.isPending}>
                Clore le dossier
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </>
  );
}
