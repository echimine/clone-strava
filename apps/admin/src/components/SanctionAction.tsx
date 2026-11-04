"use client";

import { Button } from "@repo/ui/components/button";
import { useState, type ReactNode } from "react";
import { toast } from "sonner";
import { SanctionDialog } from "@/components/SanctionDialog";

export type SanctionActionProps = {
  /** The button that opens the dialog. */
  trigger: { label: string; ariaLabel?: string; variant?: "destructive" | "outline" | "ghost" };
  title: string;
  summary: ReactNode;
  confirmLabel: string;
  /** Shown once done. */
  successMessage: string;
  /** Runs the action with the reason (a mutation's `mutateAsync`). */
  run: (reason: string) => Promise<unknown>;
  onDone?: () => void;
  /** Extra fields between the summary and the reason (a Ban's duration, a typed confirmation). */
  children?: ReactNode;
  /** False while those extra fields are not filled in. */
  canConfirm?: boolean;
  /** `false` for an action that is not a Sanction (the admin role): optional reason. */
  reasonRequired?: boolean;
  /** Overrides « Ce motif sera lu par l'athlète. » under a required reason. */
  reasonNotice?: ReactNode;
  /** Disables the button, with `disabledReason` as its tooltip (« RevenueCat non configuré »). */
  disabled?: boolean;
  disabledReason?: string;
  /** Called when the dialog opens or closes, e.g. to reset the extra fields. */
  onOpenChange?: (open: boolean) => void;
};

/**
 * A button opening the shared Sanction dialog (ADR-038 §4: a required reason the athlete reads),
 * which runs the action with the reason, toasts, and closes; an error stays in the dialog. Shared
 * by every backoffice screen with Sanctions (Activities, users…).
 */
export function SanctionAction({
  trigger,
  title,
  summary,
  confirmLabel,
  successMessage,
  run,
  onDone,
  children,
  canConfirm,
  reasonRequired,
  reasonNotice,
  disabled,
  disabledReason,
  onOpenChange,
}: SanctionActionProps) {
  const [open, setOpen] = useState(false);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function changeOpen(next: boolean) {
    setOpen(next);
    onOpenChange?.(next);
  }

  async function confirm(reason: string) {
    setPending(true);
    setError(null);
    try {
      await run(reason);
      toast.success(successMessage);
      changeOpen(false);
      onDone?.();
    } catch (caught: unknown) {
      setError(caught instanceof Error ? caught.message : "Une erreur est survenue");
    } finally {
      setPending(false);
    }
  }

  return (
    <>
      <Button
        variant={trigger.variant ?? "outline"}
        size="sm"
        aria-label={trigger.ariaLabel}
        disabled={disabled}
        title={disabled ? disabledReason : undefined}
        onClick={() => {
          setError(null);
          changeOpen(true);
        }}
      >
        {trigger.label}
      </Button>
      <SanctionDialog
        open={open}
        onOpenChange={changeOpen}
        title={title}
        summary={summary}
        confirmLabel={confirmLabel}
        onConfirm={(reason) => void confirm(reason)}
        canConfirm={canConfirm}
        reasonRequired={reasonRequired}
        reasonNotice={reasonNotice}
        isPending={pending}
        error={error}
      >
        {children}
      </SanctionDialog>
    </>
  );
}
