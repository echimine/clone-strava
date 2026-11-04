import { describe, expect, it } from "vitest";
import { z } from "zod";
import {
  adminListQuerySchema,
  adminListResponseSchema,
  adminPeriodQuerySchema,
  adminSortQuerySchema,
} from "./list.js";
import { adminOptionalReasonSchema, adminReasonSchema } from "./reason.js";

describe("admin list conventions (ADR-038 §2)", () => {
  it("defaults to the first page of 50", () => {
    expect(adminListQuerySchema.parse({})).toEqual({ page: 1, pageSize: 50 });
  });

  it("reads page and page size from query strings", () => {
    expect(adminListQuerySchema.parse({ page: "3", pageSize: "100" })).toEqual({ page: 3, pageSize: 100 });
  });

  it("accepts only 25, 50 or 100 rows per page", () => {
    expect(adminListQuerySchema.safeParse({ pageSize: "30" }).success).toBe(false);
    expect(adminListQuerySchema.safeParse({ page: "0" }).success).toBe(false);
  });

  it("trims the search and drops an empty one", () => {
    expect(adminListQuerySchema.parse({ q: "  Émile " }).q).toBe("Émile");
    expect(adminListQuerySchema.parse({ q: "   " }).q).toBeUndefined();
  });

  it("sorts from a whitelist, with a default sort", () => {
    const schema = adminSortQuerySchema(["createdAt", "lastActivityAt"], { sort: "createdAt", order: "desc" });
    expect(schema.parse({})).toEqual({ sort: "createdAt", order: "desc" });
    expect(schema.parse({ sort: "lastActivityAt", order: "asc" })).toEqual({ sort: "lastActivityAt", order: "asc" });
    expect(schema.safeParse({ sort: "email" }).success).toBe(false);
  });

  it("takes a period as calendar dates, from before to", () => {
    expect(adminPeriodQuerySchema.parse({ from: "2026-11-01", to: "2026-11-04" })).toEqual({
      from: "2026-11-01",
      to: "2026-11-04",
    });
    expect(adminPeriodQuerySchema.safeParse({ from: "2026-11-05", to: "2026-11-04" }).success).toBe(false);
    expect(adminPeriodQuerySchema.safeParse({ from: "04/11/2026" }).success).toBe(false);
  });

  it("answers with items, total, page and page size", () => {
    const schema = adminListResponseSchema(z.object({ id: z.string() }));
    const page = { items: [{ id: "a" }], total: 51, page: 2, pageSize: 50 };
    expect(schema.parse(page)).toEqual(page);
  });
});

describe("admin reasons (ADR-038 §4)", () => {
  it("requires a non-empty reason, trimmed", () => {
    expect(adminReasonSchema.parse("  Propos haineux ")).toBe("Propos haineux");
    expect(adminReasonSchema.safeParse("   ").success).toBe(false);
    expect(adminReasonSchema.safeParse(undefined).success).toBe(false);
  });

  it("reads an empty optional reason as no reason", () => {
    expect(adminOptionalReasonSchema.parse("  ")).toBeUndefined();
    expect(adminOptionalReasonSchema.parse(undefined)).toBeUndefined();
    expect(adminOptionalReasonSchema.parse(" Demande ")).toBe("Demande");
  });
});
