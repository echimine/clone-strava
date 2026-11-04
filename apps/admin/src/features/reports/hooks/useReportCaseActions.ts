import type { BanDuration } from "@repo/contracts";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import {
  banUser,
  closeReportCase,
  deleteActivity,
  removeComment,
  removeMedia,
  resetActivityText,
  resetProfile,
  type ProfileReset,
} from "@/features/reports/api";
import { foreignKeys, reportKeys } from "@/features/reports/query-keys";

/** How long after a deletion the case is read again: `moderation` closes it asynchronously. */
const AUTO_CLOSE_DELAY_MS = 1_000;

/**
 * The actions of a case (ADR-038 §10): the Sanctions its target offers, the author's Ban, and
 * « Clore ». Each refreshes the queue, the Journal and the screens a Sanction changes; a deletion
 * closes the case by itself, which the detail shows once read again.
 */
export function useReportCaseActions(caseId: string) {
  const queryClient = useQueryClient();
  const refresh = async () => {
    await Promise.all(
      [reportKeys.all, ...foreignKeys].map((queryKey) => queryClient.invalidateQueries({ queryKey })),
    );
  };
  const afterSanction = async () => {
    await refresh();
    setTimeout(() => void queryClient.invalidateQueries({ queryKey: reportKeys.all }), AUTO_CLOSE_DELAY_MS);
  };

  return {
    removeComment: useMutation({
      mutationFn: ({ commentId, reason }: { commentId: string; reason: string }) => removeComment(commentId, reason),
      onSuccess: afterSanction,
    }),
    deleteActivity: useMutation({
      mutationFn: ({ activityId, reason }: { activityId: string; reason: string }) =>
        deleteActivity(activityId, reason),
      onSuccess: afterSanction,
    }),
    removeMedia: useMutation({
      mutationFn: ({ activityId, mediaId, reason }: { activityId: string; mediaId: string; reason: string }) =>
        removeMedia(activityId, mediaId, reason),
      onSuccess: afterSanction,
    }),
    resetText: useMutation({
      mutationFn: ({ activityId, reason }: { activityId: string; reason: string }) =>
        resetActivityText(activityId, reason),
      onSuccess: afterSanction,
    }),
    resetProfile: useMutation({
      mutationFn: ({ userId, reset, reason }: { userId: string; reset: ProfileReset; reason: string }) =>
        resetProfile(userId, reset, reason),
      onSuccess: afterSanction,
    }),
    ban: useMutation({
      mutationFn: ({ userId, duration, reason }: { userId: string; duration: BanDuration; reason: string }) =>
        banUser(userId, duration, reason),
      onSuccess: afterSanction,
    }),
    close: useMutation({
      mutationFn: ({ outcome, note }: { outcome: "resolve" | "dismiss"; note: string }) =>
        closeReportCase(caseId, outcome, note),
      onSuccess: refresh,
    }),
  };
}
