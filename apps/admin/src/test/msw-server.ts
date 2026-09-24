import { setupServer } from "msw/node";

/** Shared MSW server for tests (ADR-013 §"Tests"): mocks the API. */
export const server = setupServer();
