import { z } from "zod";

/** `user_profile.gender` (ADR-035 §4). */
export const genderSchema = z.enum(["male", "female", "non_binary", "undisclosed"]);
export type Gender = z.infer<typeof genderSchema>;

/** `user_profile.level` (ADR-035 §4). */
export const athleteLevelSchema = z.enum(["beginner", "intermediate", "advanced", "professional"]);
export type AthleteLevel = z.infer<typeof athleteLevelSchema>;

/** `user_profile.goals` (ADR-035 §4). */
export const goalSchema = z.enum([
  "compete",
  "discover_routes",
  "health",
  "meet_athletes",
  "train_for_event",
  "build_habit",
]);
export type Goal = z.infer<typeof goalSchema>;

const personName = z.string().trim().min(1).max(100);

function withoutDuplicates(values: readonly string[]): boolean {
  return new Set(values).size === values.length;
}

/**
 * `PUT /v1/me/onboarding-answers` body (ADR-035 §1, §5). The server also
 * checks what the contract cannot: an age of at least 15 and active sport codes.
 */
export const onboardingAnswersRequestSchema = z.object({
  firstName: personName,
  lastName: personName,
  /** `YYYY-MM-DD`. */
  birthDate: z.iso.date(),
  gender: genderSchema,
  /** At least one, in the order of selection. */
  sportCodes: z.array(z.string().min(1)).min(1).refine(withoutDuplicates, "Duplicate sport code"),
  /** Possibly empty when the question was skipped. */
  goals: z.array(goalSchema).max(goalSchema.options.length).refine(withoutDuplicates, "Duplicate goal"),
  level: athleteLevelSchema,
});
export type OnboardingAnswersRequest = z.infer<typeof onboardingAnswersRequestSchema>;
