import { useQuery } from "@tanstack/react-query";
import { listAuditActors } from "@/features/audit/api";
import { auditKeys } from "@/features/audit/query-keys";

/** Everyone who authored an entry, for the author filter. */
export function useAuditActors() {
  return useQuery({
    queryKey: auditKeys.actors(),
    queryFn: ({ signal }) => listAuditActors(signal),
  });
}
