import { apiErrorResponseSchema, type ApiError } from "@repo/contracts";
import type { ZodType, z } from "zod";

/**
 * Single HTTP client to the API (ADR-004, ADR-013).
 *
 * Every network call goes through here: base URL (`/api`, same origin,
 * proxied to the NestJS API by `next.config.ts`), credentials, JSON,
 * response validation with the schemas from `@repo/contracts`, and
 * normalized errors. A `401` redirects to `/login`.
 */

const BASE_URL = "/api";

/** Normalized error thrown by `apiClient` for every non-2xx response. */
export class ApiClientError extends Error {
  readonly status: number;
  readonly code: string;
  readonly details: ApiError["details"];

  constructor(status: number, error: ApiError) {
    super(error.message);
    this.name = "ApiClientError";
    this.status = status;
    this.code = error.code;
    this.details = error.details;
  }
}

type RequestOptions = {
  method?: "GET" | "POST" | "PATCH" | "PUT" | "DELETE";
  body?: unknown;
  searchParams?: Record<string, string | number | boolean | undefined>;
  signal?: AbortSignal;
};

function buildUrl(path: string, searchParams?: RequestOptions["searchParams"]) {
  const url = new URL(`${BASE_URL}${path}`, window.location.origin);
  if (searchParams) {
    for (const [key, value] of Object.entries(searchParams)) {
      if (value !== undefined) {
        url.searchParams.set(key, String(value));
      }
    }
  }
  return url.pathname + url.search;
}

async function parseErrorResponse(response: Response): Promise<ApiError> {
  try {
    const json: unknown = await response.json();
    const parsed = apiErrorResponseSchema.safeParse(json);
    if (parsed.success) {
      return parsed.data.error;
    }
  } catch {
    // response body was not JSON, fall through to the generic error below
  }
  return {
    code: "unknown_error",
    message: response.statusText || "Une erreur est survenue",
  };
}

/**
 * Performs a request against the API and validates the JSON response with
 * `schema`. Throws `ApiClientError` on any non-2xx response; on `401`,
 * redirects to `/login` (client-side only) before throwing.
 */
export async function apiClient<Schema extends ZodType>(
  path: string,
  schema: Schema,
  options: RequestOptions = {},
): Promise<z.infer<Schema>> {
  const response = await fetch(buildUrl(path, options.searchParams), {
    method: options.method ?? "GET",
    credentials: "include",
    signal: options.signal,
    headers: {
      Accept: "application/json",
      ...(options.body !== undefined ? { "Content-Type": "application/json" } : {}),
    },
    body: options.body !== undefined ? JSON.stringify(options.body) : undefined,
  });

  if (!response.ok) {
    const error = await parseErrorResponse(response);
    if (response.status === 401 && typeof window !== "undefined") {
      // Outside React (no router here): hard navigation to the sign-in page (ADR-013, errors).
      // eslint-disable-next-line @next/next/no-location-assign-relative-destination
      window.location.href = "/login";
    }
    throw new ApiClientError(response.status, error);
  }

  if (response.status === 204) {
    return schema.parse(undefined);
  }

  const json: unknown = await response.json();
  return schema.parse(json);
}
