/**
 * Port: which `sport_type` codes are active (ADR-035 §5). `users` depends on
 * no module (ADR-021 §2), so it defines what it needs here and the app
 * composing the modules supplies an adapter backed by `sports`.
 */
export interface ActiveSportCatalog {
  activeCodes(): Promise<ReadonlySet<string>>;
}
