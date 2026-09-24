// @ts-check
/**
 * Automatic enforcement of the module boundary rules of ADR-021
 * ("Bounded contexts and module boundaries"), run as `pnpm check-deps:run`
 * (`turbo run //#check-deps`, ADR-021 §9). Checked independently of the
 * linter choice, on every pull request.
 *
 * Encodes, in order:
 *  1. a `packages/core/src/<module>` is only reachable, from outside that
 *     module, through its `index.ts` (§6 "Public API = index.ts", §9.1);
 *  2. the ADR-021 §2 allow-list between core domain modules (layered,
 *     acyclic dependency graph);
 *  3. `domain/` is pure: no NestJS, no Drizzle, no `repositories/` (§6, §9.2);
 *  4. only the `realtime` platform module may import `@repo/realtime`
 *     from within `packages/core` (§2, §4, §9.4);
 *  5. the app matrix of §8 (§9);
 *  6. no circular dependencies (§9.6).
 *
 * See "Alternatives Considered" in ADR-021 for why this replaces
 * `eslint-plugin-boundaries`.
 */

/** Domain modules of `packages/core` (ADR-021 §1 table, domain kind only). */
const DOMAIN_MODULES = [
  "auth",
  "users",
  "sports",
  "social",
  "activities",
  "engagement",
  "segments",
  "subscriptions",
];

/**
 * ADR-021 §2 "Allowed dependencies between modules": each domain module may
 * depend, among core domain modules, only on the modules listed here (plus
 * itself). Platform modules (`analytics`, `storage`) are always allowed for
 * every domain module and are therefore not restricted by this table; the
 * `realtime` platform module is never allowed for a domain module (rule 4
 * below), including for the modules with an empty list here.
 */
const ALLOWED_DEPENDENCIES = {
  auth: [],
  users: [],
  sports: [],
  subscriptions: [],
  social: ["users"],
  activities: ["sports", "users", "social"],
  engagement: ["activities", "social", "users"],
  segments: ["activities", "sports"],
};

/** One `forbidden` rule per domain module, from the allow-list above. */
const moduleBoundaryRules = DOMAIN_MODULES.map((mod) => {
  const allowed = new Set([mod, ...ALLOWED_DEPENDENCIES[mod]]);
  const forbiddenTargets = DOMAIN_MODULES.filter((target) => !allowed.has(target));
  if (forbiddenTargets.length === 0) {
    return null;
  }
  return {
    name: `core-module-boundary-${mod}`,
    comment: `ADR-021 §2: '${mod}' may depend, among core domain modules, only on [${
      ALLOWED_DEPENDENCIES[mod].join(", ") || "(none)"
    }]`,
    severity: "error",
    from: { path: `^packages/core/src/${mod}/` },
    to: { path: `^packages/core/src/(${forbiddenTargets.join("|")})/` },
  };
}).filter(Boolean);

module.exports = {
  forbidden: [
    // --- 1. module internals reachable only through index.ts (§6, §9.1) ---
    {
      name: "core-module-internal-only-via-index",
      comment:
        "A packages/core module's internals (anything but index.ts) may only be " +
        "imported from within that same module; every other importer (another " +
        "core module, or an app) must go through its index.ts (ADR-021 §6, §9.1)",
      severity: "error",
      from: { path: "^packages/core/src/([^/]+)/" },
      to: {
        path: "^packages/core/src/[^/]+/.+\\.ts$",
        pathNot: "^packages/core/src/([^/]+/index\\.ts|$1/.+)$",
      },
    },
    {
      name: "app-core-module-internal-only-via-index",
      comment:
        "An app may only import a packages/core module through its index.ts " +
        "(ADR-021 §6, §9.1)",
      severity: "error",
      from: { path: "^apps/[^/]+/" },
      to: {
        path: "^packages/core/src/[^/]+/.+\\.ts$",
        pathNot: "^packages/core/src/[^/]+/index\\.ts$",
      },
    },

    // --- 2. ADR-021 §2 allow-list between core domain modules ---
    ...moduleBoundaryRules,

    // --- 3. domain/ is pure (§6, §9.2) ---
    {
      name: "domain-no-nestjs",
      comment: "ADR-021 §6/§9.2: domain/ is pure — no NestJS decorators or DI",
      severity: "error",
      from: { path: "^packages/core/src/[^/]+/domain/" },
      to: { path: "node_modules/@nestjs" },
    },
    {
      name: "domain-no-drizzle",
      comment: "ADR-021 §6/§9.2: domain/ is pure — no Drizzle/DB access",
      severity: "error",
      from: { path: "^packages/core/src/[^/]+/domain/" },
      to: { path: "node_modules/drizzle-orm" },
    },
    {
      name: "domain-no-repositories",
      comment: "ADR-021 §6/§9.2: domain/ never imports a module's repositories/",
      severity: "error",
      from: { path: "^packages/core/src/[^/]+/domain/" },
      to: { path: "/repositories/" },
    },

    // --- 4. only the realtime platform module imports @repo/realtime (§2, §4, §9.4) ---
    {
      name: "only-realtime-module-imports-repo-realtime",
      comment:
        "ADR-021 §2/§4/§9.4: only packages/core/src/realtime may import " +
        "@repo/realtime; domain modules emit domain events instead",
      severity: "error",
      from: { path: "^packages/core/src/(?!realtime/)[^/]+/" },
      to: { path: "^packages/realtime/" },
    },

    // --- 5. app matrix (ADR-021 §8, §9) ---
    {
      name: "app-realtime-no-core-no-db",
      comment: "ADR-021 §8/§10: apps/realtime has no @repo/core, no @repo/db",
      severity: "error",
      from: { path: "^apps/realtime/" },
      to: { path: "^packages/(core|db)/" },
    },
    {
      name: "app-admin-no-core-no-db",
      comment:
        "ADR-021 §8/§4: apps/admin only talks to the API — no @repo/core, no " +
        "@repo/db, no direct drizzle-orm/ioredis access",
      severity: "error",
      from: { path: "^apps/admin/" },
      to: { path: "^packages/(core|db)/|node_modules/(drizzle-orm|ioredis)" },
    },
    {
      name: "no-app-imports-app",
      comment: "ADR-021 §8/ADR-005: no app imports another app",
      severity: "error",
      from: { path: "^apps/([^/]+)/" },
      to: { path: "^apps/(?!$1/)[^/]+/" },
    },

    // --- 6. no circular dependencies (§9.6) ---
    {
      name: "no-circular",
      comment: "ADR-021 §9.6: the module graph is acyclic",
      severity: "error",
      from: {},
      to: { circular: true },
    },
  ],
  options: {
    parser: "swc",
    doNotFollow: { path: "node_modules" },
    exclude: {
      path: "(^|/)(dist|\\.next|\\.turbo|coverage)(/|$)|^apps/mobile/",
    },
    enhancedResolveOptions: {
      exportsFields: ["exports"],
      conditionNames: ["import", "require", "node", "default", "types"],
    },
    tsPreCompilationDeps: true,
  },
};
