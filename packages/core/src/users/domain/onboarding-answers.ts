import type { AthleteLevel, Gender, Goal, OnboardingAnswersRequest } from "@repo/contracts";

/** ADR-035 §5: the Onboarding is refused under this age. */
export const MINIMUM_AGE_YEARS = 15;

/**
 * Whether someone born on `birthDate` (`YYYY-MM-DD`) is at least
 * {@link MINIMUM_AGE_YEARS} on `today` (`YYYY-MM-DD`), to the day: the
 * comparison is on strings, so a 29 February birthday counts from 1 March.
 */
export function isOldEnough(birthDate: string, today: string): boolean {
  const year = Number(today.slice(0, 4)) - MINIMUM_AGE_YEARS;
  return birthDate <= `${String(year).padStart(4, "0")}${today.slice(4)}`;
}

/** The profile fields the Onboarding answers fill (ADR-035 §4). */
export interface OnboardingProfileFields {
  firstName: string | null;
  lastName: string | null;
  birthDate: string | null;
  gender: Gender | null;
  level: AthleteLevel | null;
  goals: Goal[] | null;
}

/** ADR-035 §5 "only fills what is empty": the answers for the fields that are still `null`. */
export function emptyFieldsFilledBy(
  profile: OnboardingProfileFields,
  answers: OnboardingAnswersRequest,
): Partial<OnboardingProfileFields> {
  const patch: Partial<OnboardingProfileFields> = {};
  if (profile.firstName === null) patch.firstName = answers.firstName;
  if (profile.lastName === null) patch.lastName = answers.lastName;
  if (profile.birthDate === null) patch.birthDate = answers.birthDate;
  if (profile.gender === null) patch.gender = answers.gender;
  if (profile.level === null) patch.level = answers.level;
  if (profile.goals === null) patch.goals = answers.goals;
  return patch;
}
