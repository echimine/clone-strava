import { keepPreviousData, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { listFailures, relaunchAll, relaunchOne, type FailureKind, type PageQuery } from "@/features/jobs/api";
import { activitiesKey, jobKeys, journalKey } from "@/features/jobs/query-keys";

/** A page of one "Échecs" list (ADR-038 §14). */
export function useFailureList<Kind extends FailureKind>(kind: Kind, query: PageQuery) {
  return useQuery({
    queryKey: jobKeys.failureList(kind, query),
    queryFn: ({ signal }) => listFailures(kind, query, signal),
    placeholderData: keepPreviousData,
  });
}

/**
 * The relaunches of one "Échecs" list: one failure through its domain action, or the batch.
 * Each refreshes the failures, the queues, the Activities and the Journal.
 */
export function useFailureActions(kind: FailureKind) {
  const queryClient = useQueryClient();
  const refresh = async () => {
    await Promise.all(
      [jobKeys.all, activitiesKey, journalKey].map((queryKey) => queryClient.invalidateQueries({ queryKey })),
    );
  };
  return {
    one: useMutation({ mutationFn: (id: string) => relaunchOne[kind](id), onSuccess: refresh }),
    all: useMutation({ mutationFn: () => relaunchAll[kind](), onSuccess: refresh }),
  };
}
