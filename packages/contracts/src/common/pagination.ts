import { z } from "zod";

/** Page-based pagination query params, shared by every list endpoint. */
export const paginationQuerySchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});
export type PaginationQuery = z.infer<typeof paginationQuerySchema>;

/** Builds the response schema for a paginated list of `itemSchema`. */
export function paginatedResponseSchema<T extends z.ZodType>(itemSchema: T) {
  return z.object({
    items: z.array(itemSchema),
    page: z.number().int(),
    limit: z.number().int(),
    total: z.number().int(),
  });
}
export type PaginatedResponse<T> = {
  items: T[];
  page: number;
  limit: number;
  total: number;
};
