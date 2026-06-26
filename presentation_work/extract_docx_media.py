import sys
import zipfile
from pathlib import Path

from PIL import Image


def main():
    docx_path = Path(sys.argv[1])
    out_dir = Path(sys.argv[2])
    out_dir.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(docx_path) as zf:
        for name in zf.namelist():
            if not name.startswith("word/media/"):
                continue
            data = zf.read(name)
            out_path = out_dir / Path(name).name
            out_path.write_bytes(data)
            try:
                with Image.open(out_path) as img:
                    print(out_path.name, img.size)
            except Exception:
                print(out_path.name, "non-image")


if __name__ == "__main__":
    main()
