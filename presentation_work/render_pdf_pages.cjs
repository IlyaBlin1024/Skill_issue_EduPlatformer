const fs = require("fs");
const path = require("path");
const { pathToFileURL } = require("url");
const { createCanvas } = require("@napi-rs/canvas");

const pdfPath = process.argv[2];
const outDir = process.argv[3];
const maxPages = Number(process.argv[4] || 3);

const pdfjsPath = "C:/Users/bli34/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/pdfjs-dist/legacy/build/pdf.mjs";

class NodeCanvasFactory {
  create(width, height) {
    const canvas = createCanvas(width, height);
    const context = canvas.getContext("2d");
    return { canvas, context };
  }
  reset(canvasAndContext, width, height) {
    canvasAndContext.canvas.width = width;
    canvasAndContext.canvas.height = height;
  }
  destroy(canvasAndContext) {
    canvasAndContext.canvas.width = 0;
    canvasAndContext.canvas.height = 0;
    canvasAndContext.canvas = null;
    canvasAndContext.context = null;
  }
}

(async () => {
  fs.mkdirSync(outDir, { recursive: true });
  const pdfjsLib = await import(pathToFileURL(pdfjsPath).href);
  pdfjsLib.GlobalWorkerOptions.workerSrc = "C:/Users/bli34/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/pdfjs-dist/legacy/build/pdf.worker.mjs";
  const data = new Uint8Array(fs.readFileSync(pdfPath));
  const loadingTask = pdfjsLib.getDocument({ data, useWorkerFetch: false, isEvalSupported: false, disableFontFace: false });
  const pdf = await loadingTask.promise;
  const pageCount = Math.min(pdf.numPages, maxPages);
  for (let pageNo = 1; pageNo <= pageCount; pageNo++) {
    const page = await pdf.getPage(pageNo);
    const viewport = page.getViewport({ scale: 1.6 });
    const canvasFactory = new NodeCanvasFactory();
    const canvasAndContext = canvasFactory.create(viewport.width, viewport.height);
    await page.render({
      canvasContext: canvasAndContext.context,
      viewport,
      canvasFactory,
    }).promise;
    fs.writeFileSync(path.join(outDir, `page-${pageNo}.png`), canvasAndContext.canvas.toBuffer("image/png"));
    canvasFactory.destroy(canvasAndContext);
  }
})();
