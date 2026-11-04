import { useMutation, useQueryClient } from "@tanstack/react-query";
import {
  deleteActivity,
  removeComment,
  removeMedia,
  reprocessActivity,
  resetActivityText,
} from "@/features/activities/api";
import { activityKeys, journalKey } from "@/features/activities/query-keys";

/**
 * The actions of an Activity's detail (ADR-038 §11): « Retraiter » and the four Sanctions. Each
 * refreshes the Activity, the lists and the Journal once done; the caller toasts and closes its
 * dialog.
 */
export function useActivityActions(activityId: string) {
  const queryClient = useQueryClient();
  const refresh = async () => {
    await Promise.all([
      queryClient.invalidateQueries({ queryKey: activityKeys.all }),
      queryClient.invalidateQueries({ queryKey: journalKey }),
    ]);
  };

  return {
    reprocess: useMutation({ mutationFn: () => reprocessActivity(activityId), onSuccess: refresh }),
    deleteActivity: useMutation({
      mutationFn: (reason: string) => deleteActivity(activityId, reason),
      // The detail is gone: drop it rather than refetch a 404.
      onSuccess: async () => {
        queryClient.removeQueries({ queryKey: activityKeys.detail(activityId) });
        await refresh();
      },
    }),
    removeMedia: useMutation({
      mutationFn: ({ mediaId, reason }: { mediaId: string; reason: string }) =>
        removeMedia(activityId, mediaId, reason),
      onSuccess: refresh,
    }),
    resetText: useMutation({ mutationFn: (reason: string) => resetActivityText(activityId, reason), onSuccess: refresh }),
    removeComment: useMutation({
      mutationFn: ({ commentId, reason }: { commentId: string; reason: string }) => removeComment(commentId, reason),
      onSuccess: refresh,
    }),
  };
}
