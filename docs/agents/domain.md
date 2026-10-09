# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root.
- **`docs/adr/`**: read ADRs that touch the area you're about to work in.

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates them lazily when terms or decisions actually get resolved.

## File structure

Single-context repo: one glossary and one ADR folder for the whole monorepo, even though it holds several apps and packages.

```
/
├── CONTEXT.md
├── docs/adr/
│   ├── ADR-001-global-architecture.md
│   ├── ADR-021-bounded-contexts-and-module-boundaries.md
│   └── ...
├── apps/
└── packages/
```

ADRs are named `ADR-NNN-kebab-title.md` with a three-digit sequential number. Check the highest existing number in `docs/adr/` before creating a new one.

## Amending an ADR

When a later decision amends an earlier ADR, edit the earlier ADR's content inline where it changed, marking it "Amended by ADR-XXX". Don't only add a link at the bottom.

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal: either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-008 (mobile offline sync), but worth reopening because…_
