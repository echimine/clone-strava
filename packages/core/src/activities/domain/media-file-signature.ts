import type { MediaContentType } from "@repo/contracts";

/** How many leading bytes the confirmation reads from each file (ADR-037 §4: `Range: bytes=0-15`). */
export const MEDIA_SIGNATURE_BYTES = 16;

const JPEG_START = [0xff, 0xd8, 0xff];
/** An MP4 (ISO base media file) starts with its `ftyp` box: a 4-byte size, then the type. */
const MP4_BOX_TYPE = "ftyp";

/** Whether the first bytes of a file are those of its content type (ADR-037 §4). */
export function hasMediaFileSignature(contentType: MediaContentType, head: Uint8Array): boolean {
  if (contentType === "image/jpeg") {
    return JPEG_START.every((byte, index) => head[index] === byte);
  }
  return head.length >= 8 && String.fromCharCode(...head.subarray(4, 8)) === MP4_BOX_TYPE;
}
