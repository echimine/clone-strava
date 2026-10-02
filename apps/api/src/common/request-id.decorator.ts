import { createParamDecorator, type ExecutionContext } from "@nestjs/common";
import type { Request } from "express";

/** Correlation id set by `pino-http` (`genReqId`, ADR-009 "Logs"), copied into job payloads. */
export const RequestId = createParamDecorator(
  (_data: unknown, ctx: ExecutionContext): string | undefined => {
    const id = ctx.switchToHttp().getRequest<Request & { id?: unknown }>().id;
    return id === undefined ? undefined : String(id);
  },
);
