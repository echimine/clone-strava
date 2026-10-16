import { NotFoundException } from "@nestjs/common";

/** `404 comment_not_found` (ADR-034 §3): unknown, deleted, or on another Activity. */
export function commentNotFound(): NotFoundException {
  return new NotFoundException({ code: "comment_not_found", message: "Comment not found" });
}
