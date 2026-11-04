import { ConflictException } from "@nestjs/common";
import { ACTIVITY_MEDIA_MAX } from "@repo/contracts";

/** `409 media_limit_reached` (ADR-037 §4): the Activity already has its 8 confirmed Media. */
export function mediaLimitReached(): ConflictException {
  return new ConflictException({
    code: "media_limit_reached",
    message: `An activity holds at most ${ACTIVITY_MEDIA_MAX} Media`,
  });
}

/** `409 media_missing` (ADR-037 §4): a file of the Media is not in the bucket; the phone sends again. */
export function mediaMissing(): ConflictException {
  return new ConflictException({ code: "media_missing", message: "A file of the Media is not in the bucket" });
}
