import { readdirSync } from "node:fs";
import { nextJsConfig } from "@repo/eslint-config/next-js";

const API_CLIENT_ONLY = "The admin is an API client only (ADR-004, ADR-013).";

/** Imports forbidden everywhere in the admin (ADR-013 rule 1). */
const forbiddenPaths = ["drizzle-orm", "pg", "ioredis", "@repo/db", "@repo/core"].map((name) => ({
  name,
  message: API_CLIENT_ONLY,
}));
const forbiddenPatterns = [{ group: ["@aws-sdk/*"], message: API_CLIENT_ONLY }];

/**
 * "A feature does not import another feature" (ADR-013 rule 3): one config
 * block per feature folder, forbidding every other feature. `no-restricted-imports`
 * is set per block, so each one repeats the global restrictions.
 */
const features = readdirSync(new URL("./src/features", import.meta.url), { withFileTypes: true })
  .filter((entry) => entry.isDirectory())
  .map((entry) => entry.name);

const featureBoundaries = features.map((feature) => ({
  files: [`src/features/${feature}/**`],
  rules: {
    "no-restricted-imports": [
      "error",
      {
        paths: forbiddenPaths,
        patterns: [
          ...forbiddenPatterns,
          {
            group: [
              "@/features/*",
              `!@/features/${feature}`,
              `!@/features/${feature}/**`,
            ],
            message: "A feature does not import another feature (ADR-013 rule 3).",
          },
        ],
      },
    ],
  },
}));

/** @type {import("eslint").Linter.Config[]} */
export default [
  ...nextJsConfig,
  {
    rules: {
      "no-restricted-imports": ["error", { paths: forbiddenPaths, patterns: forbiddenPatterns }],
    },
  },
  ...featureBoundaries,
];
