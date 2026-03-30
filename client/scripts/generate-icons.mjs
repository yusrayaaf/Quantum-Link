#!/usr/bin/env node
/**
 * generate-icons.mjs
 * Generates PWA icons (192x192, 512x512) from the SVG logo.
 * Run: node generate-icons.mjs
 * Requires: npm install sharp
 */

import sharp from "sharp";
import { readFileSync, mkdirSync } from "fs";
import { fileURLToPath } from "url";
import { dirname, join } from "path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const svgPath = join(__dirname, "../public/logo.svg");
const outDir = join(__dirname, "../public/icons");

mkdirSync(outDir, { recursive: true });

const svg = readFileSync(svgPath);

const sizes = [192, 512];

for (const size of sizes) {
  await sharp(svg)
    .resize(size, size)
    .png()
    .toFile(join(outDir, `icon-${size}.png`));
  console.log(`✅ Generated icon-${size}.png`);
}

console.log("🎉 All icons generated in public/icons/");
