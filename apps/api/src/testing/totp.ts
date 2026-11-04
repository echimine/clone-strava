/**
 * TOTP codes for specs that enroll an Administrator in 2FA through Better Auth's real routes
 * (`/two-factor/enable` then `/two-factor/verify-totp`). Matches `@better-auth/utils`' HOTP: the
 * HMAC key is the raw secret, which `totpURI` carries base32-encoded.
 */
export async function computeTotpCode(secretBase32: string, digits = 6): Promise<string> {
  const keyBytes = base32Decode(secretBase32);
  const keyBuffer = new ArrayBuffer(keyBytes.byteLength);
  new Uint8Array(keyBuffer).set(keyBytes);
  const key = await crypto.subtle.importKey("raw", keyBuffer, { name: "HMAC", hash: { name: "SHA-1" } }, false, [
    "sign",
  ]);
  const counter = Math.floor(Date.now() / 30_000);
  const buffer = new ArrayBuffer(8);
  new DataView(buffer).setBigUint64(0, BigInt(counter), false);
  const hmac = new Uint8Array(await crypto.subtle.sign("HMAC", key, buffer));
  const offset = (hmac[hmac.length - 1] ?? 0) & 15;
  const byte = (index: number) => hmac[offset + index] ?? 0;
  const value =
    (((byte(0) & 127) << 24) | ((byte(1) & 255) << 16) | ((byte(2) & 255) << 8) | (byte(3) & 255)) % 10 ** digits;
  return value.toString().padStart(digits, "0");
}

function base32Decode(input: string): Uint8Array {
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  let bits = "";
  for (const char of input.toUpperCase().replace(/=+$/, "")) {
    const value = alphabet.indexOf(char);
    if (value !== -1) {
      bits += value.toString(2).padStart(5, "0");
    }
  }
  const bytes: number[] = [];
  for (let i = 0; i + 8 <= bits.length; i += 8) {
    bytes.push(Number.parseInt(bits.slice(i, i + 8), 2));
  }
  return Uint8Array.from(bytes);
}
