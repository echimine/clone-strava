/**
 * Topic naming (ADR-010 §4). MVP has a single topic shape: `user:{userId}`,
 * the user themselves, on all their devices.
 */

const USER_TOPIC_PREFIX = "user:";

/** Builds the topic a given user is entitled to subscribe to. */
export function userTopic(userId: string): string {
  return `${USER_TOPIC_PREFIX}${userId}`;
}

export type ParsedTopic = { kind: "user"; userId: string } | { kind: "unknown" };

/** Parses a topic string back into its structured form, if recognized. */
export function parseTopic(topic: string): ParsedTopic {
  if (topic.startsWith(USER_TOPIC_PREFIX)) {
    const userId = topic.slice(USER_TOPIC_PREFIX.length);
    if (userId.length > 0) {
      return { kind: "user", userId };
    }
  }
  return { kind: "unknown" };
}
