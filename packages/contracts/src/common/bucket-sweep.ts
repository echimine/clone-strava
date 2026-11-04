/**
 * Queue and job of the daily bucket sweep (ADR-037 §11). Worker-internal: scheduled by
 * `apps/worker`, never enqueued by a module (ADR-021 §2 rule 2). Declared here so the
 * backoffice can read the queue (ADR-038 §14).
 */
export const BUCKET_SWEEP_QUEUE_NAME = "bucket-sweep";
export const BUCKET_SWEEP_JOB_NAME = "bucket-sweep";
