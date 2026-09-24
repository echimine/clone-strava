import path from "node:path";
import type { NextConfig } from "next";

const API_INTERNAL_URL = process.env.API_INTERNAL_URL ?? "http://localhost:3001";

const nextConfig: NextConfig = {
  output: "standalone",
  // Monorepo root, two levels up from apps/admin (ADR-018 §3).
  outputFileTracingRoot: path.join(import.meta.dirname, "../.."),
  transpilePackages: ["@repo/ui"],
  async rewrites() {
    return [
      // Better Auth is mounted at /api/auth/* on the API (ADR-003).
      {
        source: "/api/auth/:path*",
        destination: `${API_INTERNAL_URL}/api/auth/:path*`,
      },
      // Every other endpoint lives under /v1 on the API (ADR-009).
      {
        source: "/api/v1/:path*",
        destination: `${API_INTERNAL_URL}/v1/:path*`,
      },
    ];
  },
};

export default nextConfig;
