import swc from "unplugin-swc";
import { defineConfig } from "vitest/config";

/** NestJS + SWC + Vitest recipe (docs.nestjs.com/recipes/swc#jest). */
export default defineConfig({
  test: {
    globals: true,
    environment: "node",
    root: "./",
    include: ["src/**/*.spec.ts"],
  },
  plugins: [swc.vite({ module: { type: "es6" } })],
});
