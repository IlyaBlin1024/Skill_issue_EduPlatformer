import html
import json
import re
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

try:
    from docx import Document
except Exception:
    Document = None

ROOT = Path.cwd()
OUT = ROOT / "presentation_hse_work" / "analysis"
OUT.mkdir(parents=True, exist_ok=True)

THESIS = Path(r"C:\Users\bli34\OneDrive\Рабочий стол\Моя заннятость\Учеба\Выпускная работа (Диплом)\Выпускная квалиффикационная работа.docx")
CURRENT_DECK = Path(r"C:\Users\bli34\OneDrive\Рабочий стол\Моя заннятость\Учеба\Выпускная работа (Диплом)\Skill Issue - презентация к защите.pptx")
TEMPLATE = Path(r"C:\Users\bli34\Downloads\Шаблон презентации ВШБ.pptx")
HTML_FILE = Path(r"C:\Users\bli34\Downloads\Как подготовиться к защите ВКР — Новости — Магистерская программа «Современный социальный анализ» — Национальный исследовательский университет «Высшая школа экономики».html")

NS = {
    "a": "http://schemas.openxmlformats.org/drawingml/2006/main",
}


def clean(text: str) -> str:
    text = html.unescape(text or "")
    text = re.sub(r"\s+", " ", text).strip()
    return text


def pptx_slide_text(path: Path):
    slides = []
    with zipfile.ZipFile(path) as z:
        names = sorted(
            [n for n in z.namelist() if re.match(r"ppt/slides/slide\d+\.xml$", n)],
            key=lambda n: int(re.search(r"slide(\d+)\.xml", n).group(1)),
        )
        for name in names:
            root = ET.fromstring(z.read(name))
            runs = [node.text or "" for node in root.findall(".//a:t", NS)]
            text = clean("\n".join(runs))
            slides.append({"slide": len(slides) + 1, "text": text})
    return slides


def docx_summary(path: Path):
    if Document is None:
        return {"error": "python-docx is not available"}
    document = Document(path)
    paragraphs = []
    headings = []
    for p in document.paragraphs:
        text = clean(p.text)
        if not text:
            continue
        item = {"style": p.style.name if p.style else "", "text": text}
        paragraphs.append(item)
        if item["style"].lower().startswith("heading") or re.match(r"^(Глава|[0-9]+\.)", text):
            headings.append(text)
    important = []
    for item in paragraphs:
        t = item["text"]
        if any(key in t.lower() for key in [
            "цель",
            "объект",
            "предмет",
            "задач",
            "архитектур",
            "godot",
            "fastapi",
            "тестирован",
            "ai",
            "ии",
        ]):
            important.append(t)
        if len(important) >= 80:
            break
    return {
        "paragraph_count": len(paragraphs),
        "headings": headings[:80],
        "important_fragments": important,
    }


def html_text(path: Path):
    raw = path.read_text(encoding="utf-8", errors="ignore")
    raw = re.sub(r"(?is)<(script|style).*?</\1>", " ", raw)
    raw = re.sub(r"(?is)<br\s*/?>", "\n", raw)
    raw = re.sub(r"(?is)</(p|div|li|h[1-6]|tr)>", "\n", raw)
    text = clean(re.sub(r"(?is)<[^>]+>", " ", raw))
    sentences = re.split(r"(?<=[.!?])\s+", text)
    relevant = [
        s for s in sentences
        if any(k in s.lower() for k in ["защит", "презентац", "слайд", "доклад", "вкр", "вопрос", "регламент"])
    ]
    return {
        "title": clean(re.sub(r"(?is).*?<title>(.*?)</title>.*", r"\1", raw)) if "<title>" in raw.lower() else "",
        "relevant_fragments": relevant[:80],
        "text_excerpt": text[:5000],
    }


data = {
    "files": {
        "thesis": str(THESIS),
        "current_deck": str(CURRENT_DECK),
        "template": str(TEMPLATE),
        "html": str(HTML_FILE),
    },
    "template_slides": pptx_slide_text(TEMPLATE),
    "current_deck_slides": pptx_slide_text(CURRENT_DECK),
    "html_guidance": html_text(HTML_FILE),
    "thesis": docx_summary(THESIS),
}

(OUT / "source_extract.json").write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
print(OUT / "source_extract.json")
