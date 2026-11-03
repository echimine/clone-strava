import type { Server } from "node:http";
import type { INestApplication } from "@nestjs/common";

/** The IPv4 loopback the integration specs call; listening on it avoids a `::`-only bind. */
export const LOOPBACK = "127.0.0.1";

/** `http://127.0.0.1:<port>` of a server listening on the loopback. */
export function loopbackUrl(server: Server): string {
  const address = server.address();
  if (typeof address !== "object" || address === null) {
    throw new Error("Server is not listening on a TCP port");
  }
  return `http://${LOOPBACK}:${address.port}`;
}

/**
 * Starts `app` on a free port of the IPv4 loopback (not `listen(0)`, which binds `::`) and
 * returns the base URL the specs call.
 */
export async function listenOnLoopback(app: INestApplication): Promise<string> {
  await app.listen(0, LOOPBACK);
  return loopbackUrl(app.getHttpServer() as Server);
}
