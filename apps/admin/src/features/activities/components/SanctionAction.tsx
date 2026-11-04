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
  /** Runs the Sanction with the reason (a mutation's `mutateAsync`). */
  run: (reason: string) => Promise<unknown>;
  onDone?: () => void;
};

/**
 * A button opening the shared Sanction dialog (ADR-038 §4: a required reason the athlete reads),
 * which runs the Sanction with the reason, toasts, and closes; an error stays in the dialog.
 */
export function SanctionAction({ trigger, title, summary, confirmLabel, successMessage, run, onDone }: SanctionActionProps) {
  const [open, setOpen] = useState(false);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function confirm(reason: string) {
    setPending(true);
    setError(null);
    try {
      await run(reason);
      toast.success(successMessage);
      setOpen(false);
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
        onClick={() => {
          setError(null);
          setOpen(true);
        }}
      >
        {trigger.label}
      </Button>
      <SanctionDialog
        open={open}
        onOpenChange={setOpen}
        title={title}
        summary={summary}
        confirmLabel={confirmLabel}
        onConfirm={(reason) => void confirm(reason)}
        isPending={pending}
        error={error}
      />
    </>
  );
}
