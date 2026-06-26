import {
  Presentation,
  PresentationFile,
  column,
  text,
  fill,
  hug,
} from "@oai/artifact-tool";

const p = Presentation.create({ slideSize: { width: 1920, height: 1080 } });
const s = p.slides.add();
s.compose(
  column({ name: "root", width: fill, height: fill, padding: 80, gap: 24 }, [
    text("Test slide", { name: "title", width: fill, height: hug, style: { fontSize: 72, bold: true, color: "#111111" } }),
    text("Body", { name: "body", width: fill, height: hug, style: { fontSize: 36, color: "#333333" } }),
  ]),
  { frame: { left: 0, top: 0, width: 1920, height: 1080 }, baseUnit: 8 },
);
console.log("slide export method", s.export.toString().slice(0, 300));
const blob = await PresentationFile.exportPptx(p);
await blob.save("presentation_work/test_output.pptx");
const png = await s.export({ format: "png" });
console.log("png type", png.constructor?.name, Object.getOwnPropertyNames(Object.getPrototypeOf(png)).join(", "));
console.log("saved");
