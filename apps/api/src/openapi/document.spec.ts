import "reflect-metadata";
import { Test } from "@nestjs/testing";
import { describe, expect, it } from "vitest";
import { createOpenApiDocument } from "./document.js";

describe("createOpenApiDocument", () => {
  it("titles the API with the Nervo brand (ADR-032 §1)", async () => {
    const moduleRef = await Test.createTestingModule({}).compile();
    const app = moduleRef.createNestApplication({ logger: false });

    const document = createOpenApiDocument(app);
    await app.close();

    expect(document.info.title).toBe("Nervo API");
  });
});
