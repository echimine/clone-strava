import { Injectable } from "@nestjs/common";
import { EventEmitter2 } from "@nestjs/event-emitter";
import {
  COMMENT_ADDED_EVENT,
  COMMENT_DELETED_EVENT,
  COMMENT_EDITED_EVENT,
  type CommentEvent,
} from "@repo/contracts";

/**
 * Comment domain events (ADR-034 §4), IDs only. Called by the use cases
 * only once a write has committed, never for a replay that wrote nothing.
 */
@Injectable()
export class CommentEvents {
  constructor(private readonly events: EventEmitter2) {}

  added(event: CommentEvent): void {
    this.events.emit(COMMENT_ADDED_EVENT, event);
  }

  edited(event: CommentEvent): void {
    this.events.emit(COMMENT_EDITED_EVENT, event);
  }

  deleted(event: CommentEvent): void {
    this.events.emit(COMMENT_DELETED_EVENT, event);
  }
}
