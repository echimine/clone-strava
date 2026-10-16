/**
 * Topic naming (ADR-010 §4). `user:{userId}`: the user themselves, on all
 * their devices, granted by the connection token. `activity:{activityId}`
 * (ADR-034 §5): anyone who can see the Activity while its detail is open,
 * granted per topic by a subscription grant.
 */

const USER_TOPIC_PREFIX = "user:";
const ACTIVITY_TOPIC_PREFIX = "activity:";

/** Builds the topic a given user is entitled to subscribe to. */
export function userTopic(userId: string): string {
  return `${USER_TOPIC_PREFIX}${userId}`;
}

/** Builds the topic of one Activity's live detail (ADR-034 §5). */
export function activityTopic(activityId: string): string {
  return `${ACTIVITY_TOPIC_PREFIX}${activityId}`;
}

export type ParsedTopic =
  | { kind: "user"; userId: string }
  | { kind: "activity"; activityId: string }
  | { kind: "unknown" };

/** Parses a topic string back into its structured form, if recognized. */
export function parseTopic(topic: string): ParsedTopic {
  if (topic.startsWith(USER_TOPIC_PREFIX)) {
    const userId = topic.slice(USER_TOPIC_PREFIX.length);
    if (userId.length > 0) {
      return { kind: "user", userId };
    }
  }
  if (topic.startsWith(ACTIVITY_TOPIC_PREFIX)) {
    const activityId = topic.slice(ACTIVITY_TOPIC_PREFIX.length);
    if (activityId.length > 0) {
      return { kind: "activity", activityId };
    }
  }
  return { kind: "unknown" };
}
