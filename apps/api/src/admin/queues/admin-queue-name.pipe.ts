import { Injectable, NotFoundException, type PipeTransform } from "@nestjs/common";
import { adminQueueNameSchema, type AdminQueueName } from "@repo/contracts";

/**
 * Parses the `:name` of `/v1/admin/queues/:name/*` against the queue whitelist of `contracts`
 * (ADR-038 §14): any other name is a queue the backoffice does not know, `404 queue_not_found`.
 */
@Injectable()
export class AdminQueueNamePipe implements PipeTransform<string, AdminQueueName> {
  transform(value: string): AdminQueueName {
    const parsed = adminQueueNameSchema.safeParse(value);
    if (!parsed.success) {
      throw new NotFoundException({ code: "queue_not_found", message: `No queue named ${value}` });
    }
    return parsed.data;
  }
}
