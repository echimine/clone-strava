"use client";

import {
  activitySourceSchema,
  processingStatusSchema,
  visibilitySchema,
} from "@repo/contracts";
import { Button } from "@repo/ui/components/button";
import { Input } from "@repo/ui/components/input";
import { Label } from "@repo/ui/components/label";
import { NativeSelect, NativeSelectOption } from "@repo/ui/components/native-select";
import { XIcon } from "lucide-react";
import { useState, type FormEvent } from "react";
import { sourceLabels, sportLabels, statusLabels, visibilityLabels } from "@/features/activities/lib/labels";
import type { ListUrlState } from "@/lib/list-url-state";

function Select({
  id,
  label,
  name,
  list,
  options,
}: {
  id: string;
  label: string;
  name: string;
  list: ListUrlState;
  options: Record<string, string>;
}) {
  return (
    <div className="flex flex-col gap-1.5">
      <Label htmlFor={id}>{label}</Label>
      <NativeSelect id={id} value={list.get(name) ?? ""} onChange={(event) => list.setFilters({ [name]: event.target.value })}>
        <NativeSelectOption value="">Tous</NativeSelectOption>
        {Object.entries(options).map(([value, text]) => (
          <NativeSelectOption key={value} value={value}>
            {text}
          </NativeSelectOption>
        ))}
      </NativeSelect>
    </div>
  );
}

/**
 * The Activities list's filters (ADR-038 §11): search over the title and the athlete's name or
 * e-mail, status, source, sport, visibility, period of the start, and the athlete a user sheet's
 * « Voir ses Activités » pre-fills. All in the URL.
 */
export function ActivityFilters({ list, athleteName }: { list: ListUrlState; athleteName?: string }) {
  const [search, setSearch] = useState(list.get("q") ?? "");
  const userId = list.get("userId");

  function submit(event: FormEvent) {
    event.preventDefault();
    list.setFilters({ q: search.trim() });
  }

  return (
    <div className="flex flex-wrap items-end gap-4">
      <form onSubmit={submit} className="flex flex-col gap-1.5">
        <Label htmlFor="activities-q">Recherche</Label>
        <Input
          id="activities-q"
          type="search"
          placeholder="Titre, nom ou e-mail"
          value={search}
          onChange={(event) => setSearch(event.target.value)}
          className="w-64"
        />
      </form>
      <Select
        id="activities-status"
        label="Statut"
        name="status"
        list={list}
        options={Object.fromEntries(processingStatusSchema.options.map((value) => [value, statusLabels[value]]))}
      />
      <Select
        id="activities-source"
        label="Source"
        name="source"
        list={list}
        options={Object.fromEntries(activitySourceSchema.options.map((value) => [value, sourceLabels[value]]))}
      />
      <Select id="activities-sport" label="Sport" name="sportTypeCode" list={list} options={sportLabels} />
      <Select
        id="activities-visibility"
        label="Visibilité"
        name="visibility"
        list={list}
        options={Object.fromEntries(visibilitySchema.options.map((value) => [value, visibilityLabels[value]]))}
      />
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="activities-from">Début du</Label>
        <Input
          id="activities-from"
          type="date"
          value={list.get("from") ?? ""}
          max={list.get("to")}
          onChange={(event) => list.setFilters({ from: event.target.value })}
        />
      </div>
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="activities-to">au</Label>
        <Input
          id="activities-to"
          type="date"
          value={list.get("to") ?? ""}
          min={list.get("from")}
          onChange={(event) => list.setFilters({ to: event.target.value })}
        />
      </div>
      {userId ? (
        <div className="flex items-center gap-1 rounded-md border px-2 py-1 text-sm">
          <span className="text-muted-foreground">Athlète :</span>
          <span>{athleteName ?? userId.slice(0, 8)}</span>
          <Button
            variant="ghost"
            size="icon"
            className="size-6"
            aria-label="Retirer le filtre sur l'athlète"
            onClick={() => list.setFilters({ userId: undefined })}
          >
            <XIcon className="size-3" />
          </Button>
        </div>
      ) : null}
    </div>
  );
}
