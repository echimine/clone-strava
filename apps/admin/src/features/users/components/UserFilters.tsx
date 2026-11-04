"use client";

import { Input } from "@repo/ui/components/input";
import { Label } from "@repo/ui/components/label";
import { NativeSelect, NativeSelectOption } from "@repo/ui/components/native-select";
import { useState, type FormEvent } from "react";
import { methodLabels, roleLabels, stateLabels } from "@/features/users/lib/labels";
import type { ListUrlState } from "@/lib/list-url-state";

function Select({
  id,
  label,
  name,
  list,
  options,
  allLabel = "Tous",
}: {
  id: string;
  label: string;
  name: string;
  list: ListUrlState;
  options: Record<string, string>;
  allLabel?: string;
}) {
  return (
    <div className="flex flex-col gap-1.5">
      <Label htmlFor={id}>{label}</Label>
      <NativeSelect id={id} value={list.get(name) ?? ""} onChange={(event) => list.setFilters({ [name]: event.target.value })}>
        <NativeSelectOption value="">{allLabel}</NativeSelectOption>
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
 * The users list's filters (ADR-038 §5): search over first name, last name and e-mail, role,
 * state, Premium yes/no (#215 details it), sign-in method, sign-up period, sort. All in the URL.
 */
export function UserFilters({ list }: { list: ListUrlState }) {
  const [search, setSearch] = useState(list.get("q") ?? "");

  function submit(event: FormEvent) {
    event.preventDefault();
    list.setFilters({ q: search.trim() });
  }

  return (
    <div className="flex flex-wrap items-end gap-4">
      <form onSubmit={submit} className="flex flex-col gap-1.5">
        <Label htmlFor="users-q">Recherche</Label>
        <Input
          id="users-q"
          type="search"
          placeholder="Prénom, nom ou e-mail"
          value={search}
          onChange={(event) => setSearch(event.target.value)}
          className="w-64"
        />
      </form>
      <Select id="users-role" label="Rôle" name="role" list={list} options={roleLabels} />
      <Select id="users-state" label="État" name="state" list={list} options={stateLabels} />
      <Select id="users-premium" label="Premium" name="premium" list={list} options={{ yes: "Oui", no: "Non" }} />
      <Select
        id="users-method"
        label="Connexion"
        name="method"
        list={list}
        options={{ email_code: methodLabels.email_code, google: methodLabels.google }}
      />
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="users-from">Inscrit du</Label>
        <Input
          id="users-from"
          type="date"
          value={list.get("from") ?? ""}
          max={list.get("to")}
          onChange={(event) => list.setFilters({ from: event.target.value })}
        />
      </div>
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="users-to">au</Label>
        <Input
          id="users-to"
          type="date"
          value={list.get("to") ?? ""}
          min={list.get("from")}
          onChange={(event) => list.setFilters({ to: event.target.value })}
        />
      </div>
      <Select
        id="users-sort"
        label="Tri"
        name="sort"
        list={list}
        allLabel="Inscription (récentes)"
        options={{ lastActivityAt: "Dernière Activité" }}
      />
    </div>
  );
}
