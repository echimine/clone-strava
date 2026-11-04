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
import { useId, useState, type FormEvent, type ReactNode } from "react";

export type SanctionDialogProps = {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  title: string;
  /** What the action does, named for the Administrator ("Le commentaire d'Émile … sera retiré."). */
  summary: ReactNode;
  confirmLabel: string;
  /** Called with the trimmed reason; the caller runs the mutation, toasts and closes. */
  onConfirm: (reason: string) => void;
  /** Extra fields between the summary and the reason (a Ban's duration, a typed confirmation). */
  children?: ReactNode;
  /** False while those extra fields are not filled in. */
  canConfirm?: boolean;
  /** `false` for an action that is not a Sanction: optional reason, no notice to the athlete. */
  reasonRequired?: boolean;
  isPending?: boolean;
  /** The action's error, shown in the dialog. */
  error?: string | null;
};

/**
 * The shared "Sanction" dialog (ADR-038 §4): a summary of the action, a required reason with the
 * reminder « Ce motif sera lu par l'athlète. », and a confirmation. Every Sanction of the
 * backoffice opens it (Ban, removals, resets, account deletion…), so a reason is never missing.
 */
export function SanctionDialog({
  open,
  onOpenChange,
  title,
  summary,
  confirmLabel,
  onConfirm,
  children,
  canConfirm = true,
  reasonRequired = true,
  isPending = false,
  error = null,
}: SanctionDialogProps) {
  const reasonId = useId();
  const noticeId = useId();
  const [reason, setReason] = useState("");
  const trimmed = reason.trim();
  const disabled = isPending || !canConfirm || (reasonRequired && trimmed.length === 0);

  function handleOpenChange(next: boolean) {
    if (!next) {
      setReason("");
    }
    onOpenChange(next);
  }

  function handleSubmit(event: FormEvent) {
    event.preventDefault();
    if (!disabled) {
      onConfirm(trimmed);
    }
  }

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent>
        <form onSubmit={handleSubmit} className="flex flex-col gap-4">
          <DialogHeader>
            <DialogTitle>{title}</DialogTitle>
            <DialogDescription>{summary}</DialogDescription>
          </DialogHeader>
          {children}
          <div className="flex flex-col gap-1.5">
            <Label htmlFor={reasonId}>{reasonRequired ? "Motif" : "Motif (facultatif)"}</Label>
            <Textarea
              id={reasonId}
              value={reason}
              maxLength={ADMIN_REASON_MAX_LENGTH}
              required={reasonRequired}
              aria-describedby={reasonRequired ? noticeId : undefined}
              onChange={(event) => setReason(event.target.value)}
            />
            {reasonRequired ? (
              <p id={noticeId} className="text-sm text-muted-foreground">
                Ce motif sera lu par l&apos;athlète.
              </p>
            ) : null}
          </div>
          {error ? (
            <p role="alert" className="text-sm text-destructive">
              {error}
            </p>
          ) : null}
          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => handleOpenChange(false)}>
              Annuler
            </Button>
            <Button type="submit" variant="destructive" disabled={disabled}>
              {confirmLabel}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
