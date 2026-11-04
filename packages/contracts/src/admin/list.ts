import { z } from "zod";

/**
 * Conventions shared by every backoffice list (ADR-038 §2, amending ADR-013 "Tables and
 * filters"): offset pagination with a total, one search box `q`, a whitelisted sort, plain
 * query-parameter filters and periods as calendar dates cut in Europe/Paris time. The keyset
 * pagination of ADR-034/036 stays for the app's infinite lists.
 *
 * A list's query schema is built from these pieces:
 *
 *     export const adminUserListQuerySchema = adminListQuerySchema
 *       .extend({
 *         ...adminSortQuerySchema(["createdAt", "lastActivityAt"], { sort: "createdAt", order: "desc" }).shape,
 *         ...adminPeriodShape,
 *         role: userRoleSchema.optional(),
 *       })
 *       .refine(isOrderedPeriod, periodOrderIssue);
 */

/** Rows per page a backoffice table offers. */
export const ADMIN_PAGE_SIZES = [25, 50, 100] as const;
export type AdminPageSize = (typeof ADMIN_PAGE_SIZES)[number];
export const ADMIN_DEFAULT_PAGE_SIZE: AdminPageSize = 50;
/** Longest search text a list accepts. */
export const ADMIN_SEARCH_MAX_LENGTH = 200;

/** `?page=1&pageSize=50`: the page (from 1) and its size (25, 50 or 100). */
export const adminPageQuerySchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce
    .number()
    .int()
    .refine((size) => (ADMIN_PAGE_SIZES as readonly number[]).includes(size), {
      message: `pageSize must be one of ${ADMIN_PAGE_SIZES.join(", ")}`,
    })
    .default(ADMIN_DEFAULT_PAGE_SIZE),
});
export type AdminPageQuery = z.infer<typeof adminPageQuerySchema>;

/**
 * `?q=`: the list's one search box, trimmed; empty means no search. Each list says which fields
 * it searches; the match ignores case and accents (`unaccent` + `ILIKE`).
 */
export const adminSearchSchema = z
  .string()
  .trim()
  .max(ADMIN_SEARCH_MAX_LENGTH)
  .optional()
  .transform((q) => (q ? q : undefined));

/** Pagination plus search: the base of every list query (`.extend` it with the list's filters). */
export const adminListQuerySchema = adminPageQuerySchema.extend({ q: adminSearchSchema });
export type AdminListQuery = z.infer<typeof adminListQuerySchema>;

export const sortOrderSchema = z.enum(["asc", "desc"]);
export type SortOrder = z.infer<typeof sortOrderSchema>;

/**
 * `?sort=<field>&order=asc|desc`, from the list's own whitelist, with its default sort. Spread its
 * `.shape` into the list's query schema.
 */
export function adminSortQuerySchema<const Field extends string>(
  fields: readonly [Field, ...Field[]],
  defaults: { sort: NoInfer<Field>; order: SortOrder },
) {
  return z.object({
    sort: z.enum(fields).default(defaults.sort as never),
    order: sortOrderSchema.default(defaults.order),
  });
}

/** A calendar date `YYYY-MM-DD`, read as a whole day in Europe/Paris time. */
export const adminDaySchema = z.iso.date();

/**
 * `?from=YYYY-MM-DD&to=YYYY-MM-DD`: a period of whole days, both ends included, cut in
 * Europe/Paris time (the API turns them into instants). Spread it into a list's query schema,
 * then `.refine(isOrderedPeriod, periodOrderIssue)` the result.
 */
export const adminPeriodShape = {
  from: adminDaySchema.optional(),
  to: adminDaySchema.optional(),
};

/** Whether a period's `from` is not after its `to` (ISO dates compare as strings). */
export function isOrderedPeriod(period: { from?: string; to?: string }): boolean {
  return !period.from || !period.to || period.from <= period.to;
}

export const periodOrderIssue = { message: "from must not be after to", path: ["from"] };

export const adminPeriodQuerySchema = z.object(adminPeriodShape).refine(isOrderedPeriod, periodOrderIssue);
export type AdminPeriodQuery = z.infer<typeof adminPeriodQuerySchema>;

/** `{ items, total, page, pageSize }`: one page of a backoffice list. */
export function adminListResponseSchema<Item extends z.ZodType>(itemSchema: Item) {
  return z.object({
    items: z.array(itemSchema),
    total: z.number().int(),
    page: z.number().int(),
    pageSize: z.number().int(),
  });
}
export type AdminListResponse<Item> = {
  items: Item[];
  total: number;
  page: number;
  pageSize: number;
};
