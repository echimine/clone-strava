import type { Gender, UpdateProfileRequest } from "@repo/contracts";

/** The `user_profile` columns "Modifier le profil" writes (ADR-036 §3); `null` clears one. */
export interface ProfileDetailsFields {
  firstName: string;
  lastName: string;
  bio?: string | null;
  city?: string | null;
  country?: string | null;
  birthDate?: string;
  gender?: Gender;
  weightKg?: number;
}

/** The columns to write: fields left out stay as they are, an empty text becomes `null`. */
export function profileFieldsOf(request: UpdateProfileRequest): ProfileDetailsFields {
  const fields: ProfileDetailsFields = { firstName: request.firstName, lastName: request.lastName };
  if (request.bio !== undefined) fields.bio = request.bio || null;
  if (request.city !== undefined) fields.city = request.city || null;
  if (request.country !== undefined) fields.country = request.country || null;
  if (request.birthDate !== undefined) fields.birthDate = request.birthDate;
  if (request.gender !== undefined) fields.gender = request.gender;
  if (request.weightKg !== undefined) fields.weightKg = request.weightKg;
  return fields;
}

/**
 * The Practiced sports with `mainSportCode` first, the others keeping their order. Returns
 * `codes` itself when it already starts with it, so the caller can skip the write.
 */
export function withMainSport(codes: string[], mainSportCode: string): string[] {
  if (codes[0] === mainSportCode) {
    return codes;
  }
  return [mainSportCode, ...codes.filter((code) => code !== mainSportCode)];
}
