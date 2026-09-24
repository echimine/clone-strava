/**
 * In-memory `topic -> connections` registry (ADR-010 §6), used by
 * `apps/realtime` to know which local connections to forward an event to.
 *
 * Generic over the connection type so the gateway can pass its own WebSocket
 * wrapper without this package depending on `ws`.
 */
export class TopicRegistry<TConn> {
  private readonly connectionsByTopic = new Map<string, Set<TConn>>();
  private readonly topicsByConnection = new Map<TConn, Set<string>>();

  /** Subscribes a connection to a topic. Idempotent. */
  subscribe(conn: TConn, topic: string): void {
    let connections = this.connectionsByTopic.get(topic);
    if (!connections) {
      connections = new Set();
      this.connectionsByTopic.set(topic, connections);
    }
    connections.add(conn);

    let topics = this.topicsByConnection.get(conn);
    if (!topics) {
      topics = new Set();
      this.topicsByConnection.set(conn, topics);
    }
    topics.add(topic);
  }

  /** Unsubscribes a connection from a topic. Idempotent, no-op if not subscribed. */
  unsubscribe(conn: TConn, topic: string): void {
    const connections = this.connectionsByTopic.get(topic);
    if (connections) {
      connections.delete(conn);
      if (connections.size === 0) {
        this.connectionsByTopic.delete(topic);
      }
    }

    const topics = this.topicsByConnection.get(conn);
    if (topics) {
      topics.delete(topic);
      if (topics.size === 0) {
        this.topicsByConnection.delete(conn);
      }
    }
  }

  /** Removes a connection from every topic it was subscribed to, e.g. on close. */
  removeConnection(conn: TConn): void {
    const topics = this.topicsByConnection.get(conn);
    if (!topics) {
      return;
    }
    for (const topic of topics) {
      const connections = this.connectionsByTopic.get(topic);
      if (connections) {
        connections.delete(conn);
        if (connections.size === 0) {
          this.connectionsByTopic.delete(topic);
        }
      }
    }
    this.topicsByConnection.delete(conn);
  }

  /** Connections currently subscribed to a topic. */
  connectionsFor(topic: string): ReadonlySet<TConn> {
    return this.connectionsByTopic.get(topic) ?? new Set();
  }

  /** Number of topics a connection is currently subscribed to (for quotas, ADR-010 §9). */
  topicCount(conn: TConn): number {
    return this.topicsByConnection.get(conn)?.size ?? 0;
  }

  /** Total number of distinct topics with at least one subscriber. */
  get size(): number {
    return this.connectionsByTopic.size;
  }
}
