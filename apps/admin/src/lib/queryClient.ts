import { QueryClient } from "@tanstack/react-query";
import { ApiClientError } from "@/lib/apiClient";

/**
 * TanStack Query configuration (ADR-012, ADR-013): a single client shared by
 * the whole app, created once per browser session in `Providers`.
 */
export function createQueryClient() {
  return new QueryClient({
    defaultOptions: {
      queries: {
        staleTime: 30_000,
        retry: (failureCount, error) => {
          if (error instanceof ApiClientError && error.status < 500) {
            return false;
          }
          return failureCount < 2;
        },
      },
      mutations: {
        retry: false,
      },
    },
  });
}
