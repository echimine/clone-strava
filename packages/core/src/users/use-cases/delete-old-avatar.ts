import type { Logger } from "@nestjs/common";
import type { StorageService } from "../../storage/index.js";

/**
 * Deletes a replaced or removed Avatar object after the commit (ADR-037 §2). The row no longer
 * points at it, so a failure is only logged: the `bucket-sweep` (ADR-037 §11) catches the orphan.
 */
export async function deleteOldAvatar(storage: StorageService, logger: Logger, key: string | null): Promise<void> {
  if (key === null) {
    return;
  }
  await storage.deleteObject(key).catch((error: unknown) => {
    logger.warn(`Old Avatar ${key} not removed: ${String(error)}`);
  });
}
