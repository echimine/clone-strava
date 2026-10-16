/**
 * Path of the auth emails' header wordmark (ADR-032 §2), a PNG since email
 * clients do not render SVG. The backoffice serves it from `public/brand/`,
 * outside its login proxy; the emails link it on the backoffice origin.
 */
export const EMAIL_WORDMARK_PATH = "/brand/nervo-wordmark-email.png";
