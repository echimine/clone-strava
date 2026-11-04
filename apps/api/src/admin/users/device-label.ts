const BROWSERS: [RegExp, string][] = [
  [/Edg(e|A|iOS)?\//, "Edge"],
  [/Firefox\/|FxiOS\//, "Firefox"],
  [/Chrome\/|CriOS\//, "Chrome"],
  [/Safari\//, "Safari"],
];

const SYSTEMS: [RegExp, string][] = [
  [/iPhone/, "iPhone"],
  [/iPad/, "iPad"],
  [/Android/, "Android"],
  [/Mac OS X|Macintosh/, "macOS"],
  [/Windows/, "Windows"],
  [/Linux/, "Linux"],
];

/**
 * A session's device as the user sheet names it (ADR-038 §5), from its user agent: « App iOS »
 * for the app (URLSession's `CFNetwork`), « Chrome sur macOS » for a browser, the raw text
 * otherwise; null without one.
 */
export function deviceLabel(userAgent: string | null): string | null {
  const text = userAgent?.trim();
  if (!text) {
    return null;
  }
  if (/CFNetwork\//.test(text)) {
    return "App iOS";
  }
  const browser = BROWSERS.find(([pattern]) => pattern.test(text))?.[1];
  const system = SYSTEMS.find(([pattern]) => pattern.test(text))?.[1];
  if (browser && system) {
    return `${browser} sur ${system}`;
  }
  return browser ?? system ?? text;
}
