import { createZodDto } from "nestjs-zod";
import { adminReasonBodySchema } from "@repo/contracts";

/** `{ reason }`: the body of a Sanction that takes nothing else (ADR-038 §4). */
export class AdminReasonBodyDto extends createZodDto(adminReasonBodySchema) {}
