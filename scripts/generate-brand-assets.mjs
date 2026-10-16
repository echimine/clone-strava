#!/usr/bin/env node
// Generates every brand PNG from the master SVGs in packages/ui/src/brand (ADR-032 §2).
// The PNGs are never drawn by hand: edit an SVG, then run `pnpm brand:generate` and commit
// the regenerated files.
import { mkdir, readFile } from "node:fs/promises";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import sharp from "sharp";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const brand = join(root, "packages/ui/src/brand");
const appIcon = join(root, "apps/mobile/StravaClone/Assets.xcassets/AppIcon.appiconset");
const admin = join(root, "apps/admin");

const ORANGE = "#FC5200"; // Theme.accent
const DARK = "#121212";
const WHITE = "#FFFFFF";
// Tinted (iOS 18+): a grey mark on a dark grey ground; the system applies the tint.
const TINTED_GROUND = "#2B2B2B";
const TINTED_MARK = "#C8C8C8";

/** Corner radius of a small tile, as on the comparison board (iOS-like, 22.37 % of the side). */
const tileRadius = (size) => Math.round(size * 0.2237 * 10) / 10;

const targets = [
  // iOS app icon, single size 1024, one file per appearance. Square and opaque: iOS masks it.
  { out: join(appIcon, "AppIcon-light.png"), svg: "nervo-symbol.svg", size: 1024, ground: ORANGE, mark: WHITE },
  { out: join(appIcon, "AppIcon-dark.png"), svg: "nervo-symbol.svg", size: 1024, ground: DARK, mark: ORANGE },
  { out: join(appIcon, "AppIcon-tinted.png"), svg: "nervo-symbol.svg", size: 1024, ground: TINTED_GROUND, mark: TINTED_MARK },
  // Admin favicon (#80): white symbol on an orange rounded tile, served through Next's
  // `app/icon.png` convention. The orange tile reads on light and dark tabs alike.
  { out: join(admin, "src/app/icon.png"), svg: "nervo-symbol.svg", size: 64, ground: ORANGE, mark: WHITE, radius: tileRadius(64) },
  // Email header (#80): white wordmark on orange, 2x for retina; email clients do not render SVG.
  // Hosted by the admin at EMAIL_WORDMARK_PATH (@repo/contracts), which the login proxy lets through.
  { out: join(admin, "public/brand/nervo-wordmark-email.png"), svg: "nervo-wordmark.svg", width: 558, ground: ORANGE, mark: WHITE },
];

/** The master's root `viewBox` as [x, y, width, height]. */
function viewBoxOf(svg, file) {
  const match = svg.match(/<svg[^>]*\sviewBox="([^"]+)"/);
  if (!match) throw new Error(`${file}: no viewBox on the root <svg>`);
  return match[1].trim().split(/[\s,]+/).map(Number);
}

/** Wraps the master in a canvas of `width` × `height` px with a solid (optionally rounded) ground. */
function composeSvg(master, { width, height, ground, mark, radius = 0 }) {
  const inner = master
    .replaceAll("currentColor", mark)
    .replace("<svg ", `<svg x="0" y="0" width="${width}" height="${height}" `);
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">
<rect width="${width}" height="${height}" rx="${radius}" ry="${radius}" fill="${ground}"/>
${inner}
</svg>`;
}

for (const target of targets) {
  const master = await readFile(join(brand, target.svg), "utf8");
  const [, , vbWidth, vbHeight] = viewBoxOf(master, target.svg);
  const width = target.size ?? target.width;
  const height = target.size ?? Math.round((width * vbHeight) / vbWidth);
  const svg = composeSvg(master, { ...target, width, height });
  await mkdir(dirname(target.out), { recursive: true });
  const image = sharp(Buffer.from(svg));
  // The app icon must be opaque (no alpha channel), or App Store validation rejects it.
  const output = target.radius ? image.png() : image.flatten({ background: target.ground }).removeAlpha().png();
  await output.toFile(target.out);
  console.log(`${relative(root, target.out)} (${width}×${height})`);
}
