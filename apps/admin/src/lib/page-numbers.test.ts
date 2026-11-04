import { describe, expect, it } from "vitest";
import { pageCount, pageNumbers } from "./page-numbers";

/** Numbered pagination of the backoffice tables (ADR-038 §2). */
describe("pageNumbers", () => {
  it("lists every page when there are few", () => {
    expect(pageNumbers(2, 5)).toEqual([1, 2, 3, 4, 5]);
  });

  it("keeps the first, the last and the current page's neighbours, with gaps between", () => {
    expect(pageNumbers(10, 20)).toEqual([1, "gap", 9, 10, 11, "gap", 20]);
  });

  it("does not hide a single page behind a gap", () => {
    expect(pageNumbers(4, 20)).toEqual([1, 2, 3, 4, 5, "gap", 20]);
    expect(pageNumbers(17, 20)).toEqual([1, "gap", 16, 17, 18, 19, 20]);
  });

  it("has one page for an empty list", () => {
    expect(pageCount(0, 50)).toBe(1);
    expect(pageCount(101, 50)).toBe(3);
    expect(pageNumbers(1, 1)).toEqual([1]);
  });
});
