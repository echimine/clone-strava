import { XMLParser } from "fast-xml-parser";
import { TrackFileError } from "./types.js";

const MAX_XML_DEPTH = 64;

export type XmlNode = Record<string, unknown>;

/** Rejects DTD entities (billion laughs / XXE) and absurd nesting before parsing (ADR-028 §5). */
function assertSafeXml(xml: string): void {
  if (/<!ENTITY/i.test(xml)) {
    throw new TrackFileError("invalid_file", "XML entity declarations are not allowed");
  }
  let depth = 0;
  for (const m of xml.matchAll(/<(\/?)[^\s!?>/][^>]*?(\/?)>/g)) {
    if (m[2]) continue; // self-closing
    depth += m[1] ? -1 : 1;
    if (depth > MAX_XML_DEPTH) throw new TrackFileError("invalid_file", "XML is nested too deeply");
  }
}

export function parseXml(bytes: Uint8Array, arrayTags: ReadonlySet<string>): XmlNode {
  const xml = new TextDecoder("utf-8").decode(bytes);
  assertSafeXml(xml);
  const parser = new XMLParser({
    ignoreAttributes: false,
    attributeNamePrefix: "@_",
    removeNSPrefix: true,
    parseTagValue: false,
    parseAttributeValue: false,
    isArray: (name) => arrayTags.has(name),
  });
  try {
    return parser.parse(xml, true) as XmlNode;
  } catch (e) {
    throw new TrackFileError("invalid_file", `Malformed XML: ${(e as Error).message}`);
  }
}

export function asNode(v: unknown): XmlNode | undefined {
  return v !== null && typeof v === "object" && !Array.isArray(v) ? (v as XmlNode) : undefined;
}

export function asArray(v: unknown): XmlNode[] {
  if (v === undefined || v === null) return [];
  return (Array.isArray(v) ? v : [v]).map(asNode).filter((n): n is XmlNode => n !== undefined);
}

/** Text content of an element, whether it has attributes or not. */
export function text(v: unknown): string | undefined {
  if (typeof v === "string" || typeof v === "number") return String(v).trim();
  const n = asNode(v);
  const t = n?.["#text"];
  return typeof t === "string" || typeof t === "number" ? String(t).trim() : undefined;
}

export function num(v: unknown): number | undefined {
  const s = text(v);
  if (s === undefined || s === "") return undefined;
  const n = Number(s);
  return Number.isFinite(n) ? n : undefined;
}

/** ISO 8601 to UTC epoch ms; a string without timezone is read as UTC. */
export function timeMs(v: unknown): number | undefined {
  const s = text(v);
  if (!s) return undefined;
  const hasTz = /(?:Z|[+-]\d{2}:?\d{2})$/i.test(s);
  const ms = Date.parse(hasTz ? s : `${s}Z`);
  return Number.isNaN(ms) ? undefined : ms;
}

/** First descendant element with this (prefix-less) name, depth-first. */
export function findDeep(node: XmlNode | undefined, key: string): unknown {
  if (!node) return undefined;
  if (key in node) return node[key];
  for (const child of Object.values(node)) {
    for (const c of Array.isArray(child) ? child : [child]) {
      const found = findDeep(asNode(c), key);
      if (found !== undefined) return found;
    }
  }
  return undefined;
}
