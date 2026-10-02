import { InjectQueue } from "@nestjs/bullmq";
import { Injectable } from "@nestjs/common";
import type { Queue } from "bullmq";
import {
  IMPORT_ACTIVITY_JOB_NAME,
  IMPORTS_QUEUE_NAME,
  importActivityJobId,
  type ImportActivityJob,
} from "@repo/contracts";
import { enqueueUnique } from "../../infrastructure/index.js";

/** Enqueues `import-activity` with its deterministic jobId (ADR-028 §9) and the ADR-028 §7 retry policy. */
@Injectable()
export class ImportJobEnqueuer {
  constructor(@InjectQueue(IMPORTS_QUEUE_NAME) private readonly queue: Queue<ImportActivityJob>) {}

  enqueue(job: ImportActivityJob): Promise<boolean> {
    return enqueueUnique(this.queue, IMPORT_ACTIVITY_JOB_NAME, job, importActivityJobId(job.importId));
  }
}
