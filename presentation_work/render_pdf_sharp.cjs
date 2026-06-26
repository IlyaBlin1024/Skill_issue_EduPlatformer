const fs = require("fs");
const path = require("path");
const sharp = require("sharp");

const pdfPath = process.argv[2];
const outDir = process.argv[3];
const maxPages = Number(process.argv[4] || 3);

(async () => {
  fs.mkdirSync(outDir, { recursive: true });
  for (let page = 0; page < maxPages; page++) {
    try {
      await sharp(pdfPath, { page, density: 150 })
        .png()
        .toFile(path.join(outDir, `page-${page + 1}.png`));
    } catch (err) {
      if (page === 0) throw err;
      break;
    }
  }
})();
