import { useQuery } from "@tanstack/react-query";
import { getTodoStats } from "@/features/dashboard/api";
import { dashboardKeys } from "@/features/dashboard/query-keys";

/** "À traiter" (ADR-038 §15): refreshed every 60 s and whenever the tab comes back. */
export function useTodoStats() {
  return useQuery({
    queryKey: dashboardKeys.todo(),
    queryFn: ({ signal }) => getTodoStats(signal),
    refetchInterval: 60_000,
    refetchOnWindowFocus: "always",
  });
}
