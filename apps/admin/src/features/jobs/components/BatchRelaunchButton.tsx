"use client";

import { ADMIN_BATCH_MAX } from "@repo/contracts";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@repo/ui/components/alert-dialog";
import { Button } from "@repo/ui/components/button";
import type { ReactNode } from "react";

/**
 * « Retraiter les N en échec » (ADR-038 §14): a confirmation that names the count, then the
 * batch, {@link ADMIN_BATCH_MAX} at most per click. No checkboxes, no filter.
 */
export function BatchRelaunchButton({
  label,
  count,
  confirmLabel,
  title,
  description,
  pending,
  onConfirm,
}: {
  label: string;
  count: number;
  confirmLabel: string;
  title: string;
  description: ReactNode;
  pending: boolean;
  onConfirm: () => void;
}) {
  return (
    <AlertDialog>
      <AlertDialogTrigger asChild>
        <Button size="sm" variant="outline" disabled={count === 0 || pending}>
          {label}
        </Button>
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>{title}</AlertDialogTitle>
          <AlertDialogDescription>
            {description}
            {count > ADMIN_BATCH_MAX ? ` ${ADMIN_BATCH_MAX} au plus par clic : relancez ensuite les suivantes.` : null}
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel>Annuler</AlertDialogCancel>
          <AlertDialogAction onClick={onConfirm}>{confirmLabel}</AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}
