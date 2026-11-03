import type { ListedObject } from "./storage.service.js";

/** An unreferenced folder of the bucket is deleted once its newest object is this old (ADR-037 §11). */
export const ORPHAN_MIN_AGE_MS = 7 * 24 * 60 * 60 * 1000;

/**
 * The keys of every folder whose newest object is more than {@link ORPHAN_MIN_AGE_MS} older than
 * `now`. `folderOf` gives the folder of an object; pass all the objects of a folder, since a
 * single recent one keeps the whole folder (a late `PUT` through a 24-hour URL, ADR-037 §11).
 */
export function staleFolderKeys<T extends ListedObject>(
  objects: readonly T[],
  folderOf: (object: T) => string,
  now: Date,
): string[] {
  const folders = new Map<string, { keys: string[]; newest: number }>();
  for (const object of objects) {
    const folder = folderOf(object);
    const entry = folders.get(folder) ?? { keys: [], newest: 0 };
    entry.keys.push(object.key);
    entry.newest = Math.max(entry.newest, object.lastModified.getTime());
    folders.set(folder, entry);
  }
  const cutoff = now.getTime() - ORPHAN_MIN_AGE_MS;
  return [...folders.values()].filter((folder) => folder.newest < cutoff).flatMap((folder) => folder.keys);
}
