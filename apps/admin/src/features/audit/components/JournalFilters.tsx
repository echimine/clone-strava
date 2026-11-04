"use client";

import { AUDIT_ACTIONS } from "@repo/contracts";
import { Button } from "@repo/ui/components/button";
import { Input } from "@repo/ui/components/input";
import { Label } from "@repo/ui/components/label";
import { NativeSelect, NativeSelectOption } from "@repo/ui/components/native-select";
import { XIcon } from "lucide-react";
import { useAuditActors } from "@/features/audit/hooks/useAuditActors";
import { auditActionLabels } from "@/features/audit/lib/labels";
import type { ListUrlState } from "@/lib/list-url-state";

const actionsByLabel = [...AUDIT_ACTIONS].sort((a, b) =>
  auditActionLabels[a].localeCompare(auditActionLabels[b], "fr"),
);

/** The Journal's filters (ADR-038 §3): author, action, athlete concerned and period, in the URL. */
export function JournalFilters({ list, subjectName }: { list: ListUrlState; subjectName?: string | null }) {
  const { data: actors } = useAuditActors();
  const subjectUserId = list.get("subjectUserId");

  return (
    <div className="flex flex-wrap items-end gap-4">
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="journal-actor">Auteur</Label>
        <NativeSelect
          id="journal-actor"
          value={list.get("actorId") ?? ""}
          onChange={(event) => list.setFilters({ actorId: event.target.value })}
        >
          <NativeSelectOption value="">Tous</NativeSelectOption>
          {(actors?.items ?? []).map((actor) => (
            <NativeSelectOption key={actor.id} value={actor.id}>
              {actor.displayName ?? `Compte supprimé (${actor.id.slice(0, 8)})`}
            </NativeSelectOption>
          ))}
        </NativeSelect>
      </div>
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="journal-action">Action</Label>
        <NativeSelect
          id="journal-action"
          value={list.get("action") ?? ""}
          onChange={(event) => list.setFilters({ action: event.target.value })}
        >
          <NativeSelectOption value="">Toutes</NativeSelectOption>
          {actionsByLabel.map((action) => (
            <NativeSelectOption key={action} value={action}>
              {auditActionLabels[action]}
            </NativeSelectOption>
          ))}
        </NativeSelect>
      </div>
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="journal-from">Du</Label>
        <Input
          id="journal-from"
          type="date"
          value={list.get("from") ?? ""}
          max={list.get("to")}
          onChange={(event) => list.setFilters({ from: event.target.value })}
        />
      </div>
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="journal-to">Au</Label>
        <Input
          id="journal-to"
          type="date"
          value={list.get("to") ?? ""}
          min={list.get("from")}
          onChange={(event) => list.setFilters({ to: event.target.value })}
        />
      </div>
      {subjectUserId ? (
        <div className="flex items-center gap-1 rounded-md border px-2 py-1 text-sm">
          <span className="text-muted-foreground">Athlète concerné :</span>
          <span>{subjectName ?? subjectUserId.slice(0, 8)}</span>
          <Button
            variant="ghost"
            size="icon"
            className="size-6"
            aria-label="Retirer le filtre sur l'athlète concerné"
            onClick={() => list.setFilters({ subjectUserId: undefined })}
          >
            <XIcon className="size-3" />
          </Button>
        </div>
      ) : null}
    </div>
  );
}
