import { NotFoundException, UnprocessableEntityException } from "@nestjs/common";

/** `422 cannot_follow_self` (ADR-036 §1), raised before any write. */
export function cannotFollowSelf(): UnprocessableEntityException {
  return new UnprocessableEntityException({ code: "cannot_follow_self", message: "You cannot follow yourself" });
}

/** `404 follow_request_not_found` (ADR-036 §1): no pending request from that athlete. */
export function followRequestNotFound(): NotFoundException {
  return new NotFoundException({ code: "follow_request_not_found", message: "Follow request not found" });
}
