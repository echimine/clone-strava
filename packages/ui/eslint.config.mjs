import { config } from "@repo/eslint-config/react-internal";

/** @type {import("eslint").Linter.Config[]} */
export default [
  ...config,
  {
    // shadcn components are vendored as-is from the registry and re-installed
    // through the MCP (ADR-012), never hand-edited: React Compiler purity rules
    // that the upstream code does not follow are turned off for these files only.
    files: ["src/components/sidebar.tsx", "src/hooks/use-mobile.ts"],
    rules: {
      "react-hooks/purity": "off",
      "react-hooks/set-state-in-effect": "off",
    },
  },
];
