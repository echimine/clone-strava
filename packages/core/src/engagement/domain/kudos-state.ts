/** Kudos of one activity after a give/remove (ADR-029), for optimistic UIs to reconcile. */
export interface KudosState {
  activityId: string;
  kudosCount: number;
  viewerHasKudoed: boolean;
}
