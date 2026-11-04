import { NotFoundException, UnprocessableEntityException } from "@nestjs/common";

/** `422 cannot_follow_self` (ADR-036 §1), raised before any write. */
export function cannotFollowSelf(): UnprocessableEntityException {
  return new UnprocessableEntityException({ code: "cannot_follow_self", message: "You cannot follow yourself" });
}

/** `422 cannot_block_self` (ADR-038 §8), raised before any write. */
export function cannotBlockSelf(): UnprocessableEntityException {
  return new UnprocessableEntityException({ code: "cannot_block_self", message: "You cannot block yourself" });
}

/**
 * `404 athlete_not_found`: between two athletes of a Block, each sees the other as nonexistent
 * (ADR-038 §8), so a follow answers as for an unknown athlete.
 */
export function blockedAthleteNotFound(): NotFoundException {
  return new NotFoundException({ code: "athlete_not_found", message: "Athlete not found" });
}

/** `404 follow_request_not_found` (ADR-036 §1): no pending request from that athlete. */
export function followRequestNotFound(): NotFoundException {
  return new NotFoundException({ code: "follow_request_not_found", message: "Follow request not found" });
}
