const { chromium } = require("playwright");
const { pathToFileURL } = require("url");
const path = require("path");

const pdfPath = process.argv[2];
const outPath = process.argv[3];

(async () => {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 }, deviceScaleFactor: 1 });
  await page.goto(pathToFileURL(path.resolve(pdfPath)).href, { waitUntil: "networkidle" });
  await page.waitForTimeout(2500);
  await page.screenshot({ path: outPath, fullPage: false });
  await browser.close();
})();
