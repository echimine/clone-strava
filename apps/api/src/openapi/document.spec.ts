import "reflect-metadata";
import { Test } from "@nestjs/testing";
import { describe, expect, it } from "vitest";
import { collapseNullableUnions, createOpenApiDocument } from "./document.js";

describe("createOpenApiDocument", () => {
  it("titles the API with the Nervo brand (ADR-032 §1)", async () => {
    const moduleRef = await Test.createTestingModule({}).compile();
    const app = moduleRef.createNestApplication({ logger: false });

    const document = createOpenApiDocument(app);
    await app.close();

    expect(document.info.title).toBe("Nervo API");
  });
});

describe("collapseNullableUnions", () => {
  it("collapses a nullable scalar into a type array", () => {
    expect(collapseNullableUnions({ anyOf: [{ type: "integer", minimum: 0 }, { type: "null" }] })).toEqual({
      type: ["integer", "null"],
      minimum: 0,
    });
  });

  it("keeps a nullable enum valid: null joins the enum, since `type` allows it", () => {
    const nullableEnum = {
      anyOf: [{ type: "string", enum: ["none", "pending", "accepted"] }, { type: "null" }],
      description: "The viewer's relation",
    };
    expect(collapseNullableUnions(nullableEnum)).toEqual({
      type: ["string", "null"],
      enum: ["none", "pending", "accepted", null],
      description: "The viewer's relation",
    });
  });
});
