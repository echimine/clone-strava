import sharp from "sharp";

/** Side of the Avatar, the same as the phone's (ADR-037 §2). */
export const AVATAR_SIDE_PX = 512;
/** Largest photo downloaded: Google's are a few dozen kB. */
const MAX_PHOTO_BYTES = 10 * 1024 * 1024;
const DOWNLOAD_TIMEOUT_MS = 15_000;

/** A photo that will never copy (gone, refused, not an image): retrying is pointless. */
export class PhotoUnusableError extends Error {
  override readonly name = "PhotoUnusableError";
}

/**
 * Google serves an account photo at any size through the `=s{px}-c` suffix of its URL; the ID
 * token's `picture` asks for 96 px. The copy asks for the Avatar's size instead, so the JPEG is not
 * blown up from a thumbnail. Any other URL (Google's letter image, another host) is kept as is.
 */
export function googlePhotoUrlAtAvatarSize(imageUrl: string): string {
  const url = new URL(imageUrl);
  if (!url.hostname.endsWith(".googleusercontent.com")) {
    return imageUrl;
  }
  url.pathname = url.pathname.replace(/=s\d+(-c)?$/, `=s${AVATAR_SIDE_PX}-c`);
  return url.toString();
}

/**
 * Downloads the photo. A `4xx` answer or a body over 10 MB is a {@link PhotoUnusableError}; a
 * network error, a timeout or a `5xx` throws a plain error, retried by the job.
 */
export async function downloadPhoto(url: string): Promise<Uint8Array> {
  const response = await fetch(url, { redirect: "follow", signal: AbortSignal.timeout(DOWNLOAD_TIMEOUT_MS) });
  if (response.status >= 400 && response.status < 500) {
    throw new PhotoUnusableError(`Photo answered ${response.status}`);
  }
  if (!response.ok) {
    throw new Error(`Photo answered ${response.status}`);
  }
  if (Number(response.headers.get("content-length") ?? 0) > MAX_PHOTO_BYTES) {
    throw new PhotoUnusableError("Photo larger than 10 MB");
  }
  const body = new Uint8Array(await response.arrayBuffer());
  if (body.byteLength > MAX_PHOTO_BYTES) {
    throw new PhotoUnusableError("Photo larger than 10 MB");
  }
  return body;
}

/**
 * Re-encodes any image sharp reads as the Avatar: a 512×512 JPEG, centre-cropped, upright
 * (EXIF orientation applied), transparency on white, no metadata kept. Anything sharp cannot read
 * is a {@link PhotoUnusableError}.
 */
export async function encodeAvatarJpeg(photo: Uint8Array): Promise<Uint8Array> {
  try {
    const jpeg = await sharp(photo, { limitInputPixels: 50_000_000 })
      .rotate()
      .resize(AVATAR_SIDE_PX, AVATAR_SIDE_PX, { fit: "cover" })
      .flatten({ background: "#ffffff" })
      .jpeg({ quality: 85, mozjpeg: true })
      .toBuffer();
    return new Uint8Array(jpeg);
  } catch (error) {
    throw new PhotoUnusableError(`Photo is not a readable image: ${String(error)}`);
  }
}
