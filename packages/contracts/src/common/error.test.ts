import { describe, expect, it } from "vitest";
import { apiErrorResponseSchema } from "./error.js";

describe("apiErrorResponseSchema", () => {
  it("parses a validation error with field details", () => {
    const result = apiErrorResponseSchema.safeParse({
      error: {
        code: "validation_error",
        message: "Invalid request body",
        details: [{ field: "email", message: "Invalid email" }],
      },
    });

    expect(result.success).toBe(true);
  });

  it("rejects a payload missing the required error code", () => {
    const result = apiErrorResponseSchema.safeParse({
      error: { message: "Invalid request body" },
    });

    expect(result.success).toBe(false);
  });
});
