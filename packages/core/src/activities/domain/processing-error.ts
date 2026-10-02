/**
 * Permanent failure of a job of the `activities` module (ADR-019 §6,
 * ADR-028 §7): invalid data, no retry. The use case has already recorded
 * the failure and emitted the domain event when it throws this; the
 * `apps/worker` processor turns it into a BullMQ `UnrecoverableError`.
 */
export class PermanentProcessingError extends Error {
  constructor(
    readonly code: string,
    message?: string,
  ) {
    super(message ?? code);
    this.name = "PermanentProcessingError";
  }
}
