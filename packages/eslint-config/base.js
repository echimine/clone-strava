import js from "@eslint/js";
import eslintConfigPrettier from "eslint-config-prettier";
import turboPlugin from "eslint-plugin-turbo";
import onlyWarn from "eslint-plugin-only-warn";
import tseslint from "typescript-eslint";

/**
 * A shared ESLint configuration for the repository.
 *
 * TypeScript sources are parsed by typescript-eslint, which only supports
 * TypeScript < 6.1: this package pins its own `typescript@6.0` for linting,
 * while builds and type-checking use the repository's TypeScript 7.
 * Rules are syntactic only (no type-aware linting).
 *
 * @type {import("eslint").Linter.Config[]}
 * */
export const config = [
  // Without a `files` pattern, flat config only lints .js/.mjs/.cjs:
  // TypeScript sources would be silently skipped.
  { files: ["**/*.{js,mjs,cjs,jsx,ts,tsx,mts,cts}"] },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  eslintConfigPrettier,
  {
    plugins: {
      turbo: turboPlugin,
    },
    rules: {
      "turbo/no-undeclared-env-vars": "warn",
      "@typescript-eslint/no-unused-vars": [
        "warn",
        { argsIgnorePattern: "^_", varsIgnorePattern: "^_" },
      ],
    },
  },
  {
    plugins: {
      onlyWarn,
    },
  },
  {
    ignores: ["dist/**"],
  },
];
