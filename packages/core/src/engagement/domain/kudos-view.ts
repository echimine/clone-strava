/**
 * One kudos of an Activity (ADR-034 §1). The athlete is an id only:
 * `apps/api` assembles identities (ADR-029 §2).
 */
export interface KudosView {
  athleteId: string;
  givenAt: Date;
}

/** A page of kudos, most recent first; `nextCursor` is null on the last page. */
export interface KudosPage {
  items: KudosView[];
  nextCursor: string | null;
}
