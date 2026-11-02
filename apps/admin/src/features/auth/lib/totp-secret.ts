/**
 * The base32 key inside an `otpauth://` URI, for the admin who types it
 * into the authenticator app instead of scanning the QR code.
 */
export function totpSecretOf(totpURI: string): string | null {
  try {
    return new URL(totpURI).searchParams.get("secret");
  } catch {
    return null;
  }
}
