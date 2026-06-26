import fs from "fs";
import path from "path";
import { PresentationFile } from "@oai/artifact-tool";

const [, , pptxPathArg, outDirArg] = process.argv;

if (!pptxPathArg || !outDirArg) {
  console.error("Usage: node render_pptx_previews.mjs <pptx> <out-dir>");
  process.exit(2);
}

const pptxPath = path.resolve(pptxPathArg);
const outDir = path.resolve(outDirArg);
fs.mkdirSync(outDir, { recursive: true });

const deck = await PresentationFile.importPptx(fs.readFileSync(pptxPath));
for (const [idx, slide] of deck.slides.items.entries()) {
  const blob = await slide.export({ format: "png" });
  const bytes = Buffer.from(await blob.arrayBuffer());
  fs.writeFileSync(path.join(outDir, `slide-${String(idx + 1).padStart(2, "0")}.png`), bytes);
}

console.log(outDir);
