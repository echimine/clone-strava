import { UnprocessableEntityException } from "@nestjs/common";
import { InvalidCursorError } from "../domain/keyset-cursor.js";

/**
 * One keyset page (ADR-034 §1, §3): decodes the client's cursor (`422 invalid_cursor` if this
 * server did not produce it), reads `limit + 1` rows to know whether another page follows, and
 * returns the page with its last row when one does, the position of the next cursor.
 */
export async function readKeysetPage<Cursor, Row>(
  query: { cursor?: string; limit: number },
  decode: (cursor: string) => Cursor,
  fetch: (cursor: Cursor | undefined, take: number) => Promise<Row[]>,
): Promise<{ rows: Row[]; boundary: Row | undefined }> {
  const cursor = query.cursor === undefined ? undefined : decodeOr422(query.cursor, decode);
  const fetched = await fetch(cursor, query.limit + 1);
  const rows = fetched.slice(0, query.limit);
  return { rows, boundary: fetched.length > query.limit ? rows.at(-1) : undefined };
}

function decodeOr422<Cursor>(value: string, decode: (cursor: string) => Cursor): Cursor {
  try {
    return decode(value);
  } catch (error) {
    if (error instanceof InvalidCursorError) {
      throw new UnprocessableEntityException({ code: "invalid_cursor", message: error.message });
    }
    throw error;
  }
}
