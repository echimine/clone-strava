import { keepPreviousData, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  getJob,
  listFailedJobs,
  listQueues,
  pauseQueue,
  resumeQueue,
  retryFailedJobs,
  retryJob,
  type PageQuery,
} from "@/features/jobs/api";
import { jobKeys, journalKey } from "@/features/jobs/query-keys";

/** Every whitelisted queue (ADR-038 §14), refreshed while the tab is open. */
export function useQueues() {
  return useQuery({ queryKey: jobKeys.queues(), queryFn: ({ signal }) => listQueues(signal), refetchInterval: 30_000 });
}

/** A page of a queue's failed jobs, newest first. */
export function useFailedJobs(queue: string | undefined, query: PageQuery) {
  return useQuery({
    queryKey: jobKeys.queueJobs(queue ?? "", query),
    queryFn: ({ signal }) => listFailedJobs(queue!, query, signal),
    enabled: queue !== undefined,
    placeholderData: keepPreviousData,
  });
}

/** One job, read-only. */
export function useJob(queue: string, id: string | undefined) {
  return useQuery({
    queryKey: jobKeys.job(queue, id ?? ""),
    queryFn: ({ signal }) => getJob(queue, id!, signal),
    enabled: id !== undefined,
  });
}

/** Retry, retry every failure, pause, resume: each refreshes the queues and the Journal. */
export function useQueueActions() {
  const queryClient = useQueryClient();
  const refresh = async () => {
    await Promise.all([
      queryClient.invalidateQueries({ queryKey: jobKeys.queues() }),
      queryClient.invalidateQueries({ queryKey: journalKey }),
    ]);
  };
  return {
    retry: useMutation({
      mutationFn: ({ queue, id }: { queue: string; id: string }) => retryJob(queue, id),
      onSuccess: refresh,
    }),
    retryFailed: useMutation({ mutationFn: (queue: string) => retryFailedJobs(queue), onSuccess: refresh }),
    pause: useMutation({ mutationFn: (queue: string) => pauseQueue(queue), onSuccess: refresh }),
    resume: useMutation({ mutationFn: (queue: string) => resumeQueue(queue), onSuccess: refresh }),
  };
}
