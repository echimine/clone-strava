import { type ArgumentsHost, Catch, type ExceptionFilter, HttpException, HttpStatus, Logger } from "@nestjs/common";
import type { Response } from "express";
import { ZodSerializationException, ZodValidationException } from "nestjs-zod";
import type { ZodError } from "zod";
import type { ApiErrorResponse } from "@repo/contracts";

/**
 * Single API error format for the whole API (ADR-009 §7): `code`, `message`,
 * and optional field-level `details` for validation errors, described in
 * `@repo/contracts` (`apiErrorResponseSchema`).
 */
@Catch()
export class GlobalExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(GlobalExceptionFilter.name);

  catch(exception: unknown, host: ArgumentsHost): void {
    const response = host.switchToHttp().getResponse<Response>();
    const { status, body } = this.toErrorResponse(exception);

    if (status >= HttpStatus.INTERNAL_SERVER_ERROR) {
      this.logger.error(exception instanceof Error ? exception.stack : exception);
    }

    response.status(status).json(body);
  }

  private toErrorResponse(exception: unknown): { status: number; body: ApiErrorResponse } {
    if (exception instanceof ZodValidationException) {
      const zodError = exception.getZodError() as ZodError;
      return {
        status: HttpStatus.UNPROCESSABLE_ENTITY,
        body: {
          error: {
            code: "validation_error",
            message: "Invalid request",
            details: zodError.issues.map((issue) => ({
              field: issue.path.join(".") || "(root)",
              message: issue.message,
            })),
          },
        },
      };
    }

    if (exception instanceof ZodSerializationException) {
      // A response failed to match its own contract schema: a server bug,
      // never a client-facing detail.
      this.logger.error(exception.getZodError());
      return {
        status: HttpStatus.INTERNAL_SERVER_ERROR,
        body: { error: { code: "internal_error", message: "Internal server error" } },
      };
    }

    if (exception instanceof HttpException) {
      const status = exception.getStatus();
      const httpResponse = exception.getResponse();
      const message = typeof httpResponse === "string" ? httpResponse : exception.message;
      return { status, body: { error: { code: httpStatusToCode(status), message } } };
    }

    return {
      status: HttpStatus.INTERNAL_SERVER_ERROR,
      body: { error: { code: "internal_error", message: "Internal server error" } },
    };
  }
}

function httpStatusToCode(status: number): string {
  switch (status) {
    case HttpStatus.BAD_REQUEST:
      return "bad_request";
    case HttpStatus.UNAUTHORIZED:
      return "unauthorized";
    case HttpStatus.FORBIDDEN:
      return "forbidden";
    case HttpStatus.NOT_FOUND:
      return "not_found";
    case HttpStatus.CONFLICT:
      return "conflict";
    case HttpStatus.UNPROCESSABLE_ENTITY:
      return "unprocessable_entity";
    case HttpStatus.TOO_MANY_REQUESTS:
      return "too_many_requests";
    default:
      return "error";
  }
}
