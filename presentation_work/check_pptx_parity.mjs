import fs from "fs";
import path from "path";
import { PresentationFile } from "@oai/artifact-tool";

const PPTX = path.resolve("presentation_work/output/Skill_Issue_defense_presentation.pptx");
const OUT = path.resolve("presentation_work/pptx_previews");

fs.mkdirSync(OUT, { recursive: true });

const bytes = fs.readFileSync(PPTX);
const deck = await PresentationFile.importPptx(bytes);

for (const [idx, slide] of deck.slides.items.entries()) {
  const blob = await slide.export({ format: "png" });
  const png = Buffer.from(await blob.arrayBuffer());
  fs.writeFileSync(path.join(OUT, `slide-${String(idx + 1).padStart(2, "0")}.png`), png);
}

console.log(PPTX);
console.log(OUT);
