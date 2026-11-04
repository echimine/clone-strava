import { Injectable } from "@nestjs/common";

/**
 * Promotional Premium ("Premium offerts actifs") for the "Croissance" band (ADR-038 §12, §15).
 *
 * Placeholder: the `promotional` store does not exist yet (spec #215), so the count is 0. #215
 * replaces this body with a call to the subscriptions module (active `premium` rows of the
 * `promotional` store at `now`, Administrators and Sandbox left out).
 */
@Injectable()
export class PromotionalPremiumSource {
  countActive(_now: Date, _excludedUserIds: readonly string[]): Promise<number> {
    return Promise.resolve(0);
  }
}
