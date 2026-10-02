import type { Redis } from "ioredis";
import type { Database } from "@repo/db";

/**
 * DI tokens for the shared infrastructure (ADR-021 §6 "supporting files"):
 * the Drizzle {@link Database} instance and the `ioredis` connection, both
 * provided once by {@link CoreInfrastructureModule} and injected into every
 * module's repositories, listeners and platform services.
 *
 * Symbols, not classes: `Database` and `Redis` are types from external
 * packages, so there is no class to use as an injection token.
 */
export const DATABASE = Symbol("DATABASE");
export const REDIS = Symbol("REDIS");

export type { Database };
export type { Redis };

/** A Drizzle transaction, as passed to `db.transaction(async (tx) => ...)`. */
export type Transaction = Parameters<Parameters<Database["transaction"]>[0]>[0];
/** Either the connection or an open transaction: repository writes accept both. */
export type DbExecutor = Database | Transaction;
