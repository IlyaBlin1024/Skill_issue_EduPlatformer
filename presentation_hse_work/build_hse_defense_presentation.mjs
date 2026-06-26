import fs from "fs";
import path from "path";
import {
  Presentation,
  PresentationFile,
  layers,
  shape,
  text,
  image,
  fill,
  fixed,
} from "@oai/artifact-tool";
import { paint } from "@oai/artifact-tool/presentation-jsx";

const W = 1920;
const H = 1080;
const OUT = path.resolve("presentation_hse_work/output");
const PREV = path.resolve("presentation_hse_work/previews");
const PPTX_PREV = path.resolve("presentation_hse_work/pptx_previews");
const ASSETS = path.resolve("presentation_work/assets");
const HSE_ASSETS = path.resolve("presentation_hse_work/assets");

for (const dir of [OUT, PREV, PPTX_PREV]) {
  fs.rmSync(dir, { recursive: true, force: true });
  fs.mkdirSync(dir, { recursive: true });
}

const C = {
  white: "#FFFFFF",
  paper: "#F6F8FC",
  navy: "#0F2D69",
  blue: "#234B9B",
  red: "#E61E3C",
  rose: "#CD5A5A",
  pink: "#F5C3C3",
  gray1: "#BFBFBF",
  gray2: "#A6A6A6",
  gray3: "#7F7F7F",
  ink: "#1F2430",
  paleBlue: "#EAF0FB",
  paleRed: "#FBE8EC",
};

const FONT = "HSE Sans";
const FOOTER_TITLE = "Разработка обучающей игры-платформера с интеграцией ИИ";
const imageCache = new Map();

function assetPath(file) {
  return file.startsWith("hse:")
    ? path.join(HSE_ASSETS, file.slice(4))
    : path.join(ASSETS, file);
}

function imageDataUrl(file) {
  const resolved = assetPath(file);
  if (!imageCache.has(resolved)) {
    const ext = path.extname(resolved).toLowerCase();
    const mime = ext === ".jpg" || ext === ".jpeg" ? "image/jpeg" : "image/png";
    const bytes = fs.readFileSync(resolved);
    imageCache.set(resolved, `data:${mime};base64,${bytes.toString("base64")}`);
  }
  return imageCache.get(resolved);
}

function box(name, left, top, width, height, color, radius = 0) {
  return shape({
    name,
    geometry: "rect",
    position: { left, top, width, height },
    width: fixed(width),
    height: fixed(height),
    fill: paint(color),
    borderRadius: radius,
  });
}

function txt(name, value, left, top, width, height, style = {}) {
  return text(value, {
    name,
    position: { left, top, width, height },
    width: fixed(width),
    height: fixed(height),
    style: {
      fontFace: FONT,
      fontSize: 25,
      color: C.ink,
      ...style,
    },
  });
}

function img(name, file, left, top, width, height, fit = "contain") {
  return image({
    name,
    dataUrl: imageDataUrl(file),
    position: { left, top, width, height },
    width: fixed(width),
    height: fixed(height),
    fit,
    alt: name,
  });
}

function line(name, left, top, width, color = C.red, height = 6) {
  return box(name, left, top, width, height, color, 0);
}

function root(slide, items, bg = C.paper) {
  slide.compose(
    layers({ name: "root", width: fill, height: fill }, [
      box("bg", 0, 0, W, H, bg),
      ...items,
    ]),
    { frame: { left: 0, top: 0, width: W, height: H }, baseUnit: 8 },
  );
}

function footer(n, section = "ВКР") {
  return [
    line(`footer-line-${n}`, 96, 1004, 1728, C.navy, 3),
    txt(`footer-title-${n}`, FOOTER_TITLE, 96, 1022, 720, 34, {
      fontSize: 19,
      color: C.gray3,
    }),
    txt(`footer-section-${n}`, section, 830, 1022, 360, 34, {
      fontSize: 19,
      color: C.gray3,
      align: "center",
    }),
    txt(`footer-page-${n}`, String(n), 1760, 1018, 64, 40, {
      fontSize: 22,
      bold: true,
      color: C.navy,
      align: "right",
    }),
  ];
}

function title(n, heading, subtitle = "", section = "ВКР") {
  return [
    txt(`num-${n}`, String(n), 96, 64, 54, 50, {
      fontSize: 34,
      bold: true,
      color: C.red,
    }),
    txt(`title-${n}`, heading, 165, 60, 1260, 98, {
      fontSize: 42,
      bold: true,
      color: C.navy,
    }),
    subtitle
      ? txt(`subtitle-${n}`, subtitle, 165, 150, 1280, 54, {
          fontSize: 24,
          color: C.gray3,
        })
      : box(`subtitle-spacer-${n}`, 0, 0, 1, 1, C.paper),
    line(`title-rule-${n}`, 165, 216, 240, C.red, 7),
    img(`hse-logo-${n}`, "hse:hse_template_image1.png", 1502, 54, 310, 122),
    ...footer(n, section),
  ];
}

function bullet(name, value, x, y, width, color = C.red, size = 25) {
  return [
    box(`${name}-dot`, x, y + 13, 10, 10, color, 5),
    txt(`${name}-text`, value, x + 28, y, width - 28, 66, {
      fontSize: size,
      color: C.ink,
    }),
  ];
}

function card(name, x, y, w, h, heading, body, accent = C.red) {
  return [
    box(`${name}-panel`, x, y, w, h, C.white, 0),
    line(`${name}-accent`, x, y, w, accent, 8),
    txt(`${name}-heading`, heading, x + 28, y + 26, w - 56, 42, {
      fontSize: 27,
      bold: true,
      color: C.navy,
    }),
    txt(`${name}-body`, body, x + 28, y + 86, w - 56, h - 112, {
      fontSize: 23,
      color: C.ink,
    }),
  ];
}

function metric(name, x, y, value, label, color = C.red) {
  return [
    txt(`${name}-value`, value, x, y, 230, 70, {
      fontSize: 58,
      bold: true,
      color,
    }),
    txt(`${name}-label`, label, x, y + 72, 320, 56, {
      fontSize: 22,
      color: C.gray3,
    }),
  ];
}

function pill(name, value, x, y, w, color = C.red) {
  return [
    box(`${name}-box`, x, y, w, 52, color, 0),
    txt(`${name}-text`, value, x + 18, y + 10, w - 36, 32, {
      fontSize: 21,
      bold: true,
      color: C.white,
    }),
  ];
}

function bar(name, x, y, label, value, color) {
  const max = 500;
  return [
    txt(`${name}-label`, label, x, y - 4, 230, 34, {
      fontSize: 22,
      color: C.ink,
    }),
    box(`${name}-bg`, x + 246, y, max, 24, "#DFE7F4", 0),
    box(`${name}-fg`, x + 246, y, Math.round(max * value / 75), 24, color, 0),
    txt(`${name}-value`, `${String(value).replace(".", ",")}%`, x + 770, y - 6, 110, 36, {
      fontSize: 21,
      bold: true,
      color: C.navy,
    }),
  ];
}

function makeDeck() {
  const deck = Presentation.create({ slideSize: { width: W, height: H } });
  let s;

  s = deck.slides.add();
  root(s, [
    box("cover-side", 0, 0, 550, H, C.navy),
    box("cover-red", 550, 0, 22, H, C.red),
    box("cover-logo-bg", 74, 60, 392, 174, C.white, 0),
    img("cover-logo", "hse:hse_template_image1.png", 96, 80, 340, 134),
    txt("cover-school", "НИУ ВШЭ\nФакультет информатики,\nматематики и компьютерных наук", 96, 790, 360, 132, {
      fontSize: 24,
      color: C.white,
      bold: true,
    }),
    txt("cover-kicker", "Выпускная квалификационная работа", 650, 84, 920, 42, {
      fontSize: 24,
      color: C.gray3,
      bold: true,
    }),
    txt("cover-title", "Разработка обучающей\nигры-платформера\nс интеграцией ИИ", 650, 196, 1030, 250, {
      fontSize: 62,
      bold: true,
      color: C.navy,
    }),
    txt("cover-subtitle", "для освоения основ программирования", 650, 486, 950, 48, {
      fontSize: 30,
      bold: true,
      color: C.red,
    }),
    txt("cover-meta", "Блинков Илья Олегович\nОП «Бизнес-информатика»\nНаучный руководитель:\nк-т информационных наук, доцент Б. И. Улитин\nНижний Новгород, 2026", 650, 684, 540, 176, {
      fontSize: 23,
      color: C.ink,
    }),
    img("cover-shot", "terminal_success.png", 1224, 568, 560, 292, "cover"),
  ], C.white);

  s = deck.slides.add();
  root(s, [
    ...title(2, "Проблема: новичок не видит результат кода сразу", "Гэп работы - связать учебную задачу, игровой результат и персональную подсказку.", "Проблема"),
    txt("problem-main", "На начальном этапе программирование часто воспринимается как абстрактный синтаксис, а ошибка - как тупик без понятного маршрута исправления.", 166, 300, 660, 150, {
      fontSize: 31,
      bold: true,
      color: C.navy,
    }),
    ...bullet("p1", "Классические тренажеры показывают ответ, но слабо удерживают мотивацию.", 166, 520, 620),
    ...bullet("p2", "Игровые подходы вовлекают, но часто не дают точной диагностики ошибки.", 166, 610, 620),
    ...bullet("p3", "ИИ-подсказка полезна только тогда, когда остается контекстной и не решает задачу за студента.", 166, 700, 620),
    box("problem-visual-bg", 910, 292, 820, 520, C.white, 0),
    img("problem-shot", "terminal_task.png", 960, 340, 720, 400, "contain"),
    line("problem-shot-line", 960, 774, 720, C.red, 8),
  ]);

  s = deck.slides.add();
  root(s, [
    ...title(3, "Цель и задачи работы", "Исследовательский вопрос: как разработать платформер для обучения основам программирования с внедрением ИИ?", "Постановка"),
    ...card("goal", 142, 294, 520, 210, "Цель", "Создать прототип обучающей игры, где код влияет на игровой прогресс, а ИИ помогает разбирать ошибки и выбирать следующий шаг.", C.red),
    ...card("obj", 700, 294, 500, 210, "Объект", "Процесс обучения основам программирования и цифровые инструменты поддержки начинающих студентов.", C.blue),
    ...card("subj", 1238, 294, 540, 210, "Предмет", "Игра-платформер как образовательный инструмент: механики, уровни, подсказки и ИИ-модуль.", C.rose),
    ...bullet("t1", "Проанализировать аналоги и подходы к game-based learning.", 186, 590, 690, C.blue),
    ...bullet("t2", "Спроектировать игровую концепцию, уровни и учебные сценарии.", 186, 680, 690, C.blue),
    ...bullet("t3", "Реализовать Godot-клиент и FastAPI-backend для заданий, проверки и подсказок.", 1000, 590, 690, C.red),
    ...bullet("t4", "Провести пилотное тестирование и оценить поведение игроков по логам.", 1000, 680, 690, C.red),
  ]);

  s = deck.slides.add();
  root(s, [
    ...title(4, "Теоретическая основа и аналоги", "В презентации оставлены только понятия, которые объясняют проектное решение.", "Теория"),
    ...card("theory1", 140, 300, 500, 250, "Game-based learning", "Игровая цель задает контекст, а обратная связь помогает закреплять понятия через действие.", C.red),
    ...card("theory2", 710, 300, 500, 250, "Constructive alignment", "Задания, механики уровня и критерии проверки должны измерять один и тот же навык.", C.blue),
    ...card("theory3", 1280, 300, 500, 250, "AI scaffolding", "ИИ используется как поддержка: подсказка, объяснение ошибки и рекомендация, а не готовое решение.", C.rose),
    txt("analogs-title", "Вывод из анализа аналогов", 164, 638, 560, 42, {
      fontSize: 30,
      bold: true,
      color: C.navy,
    }),
    ...bullet("a1", "CodeCombat и похожие системы доказывают ценность обучения через действие.", 166, 714, 690),
    ...bullet("a2", "Для ВКР важнее не масштаб платформы, а связка «уровень - код - подсказка - логирование».", 166, 804, 760),
    img("theory-loop", "game_loop.png", 1012, 630, 650, 228, "contain"),
  ]);

  s = deck.slides.add();
  root(s, [
    ...title(5, "Концепция Skill Issue: код открывает игровой прогресс", "Игрок решает учебные задачи, а результат сразу проявляется в уровне.", "Концепция"),
    img("concept", "concept.png", 150, 300, 760, 430, "contain"),
    ...pill("c-pill1", "переменные", 1010, 310, 230, C.blue),
    ...pill("c-pill2", "условия", 1270, 310, 190, C.red),
    ...pill("c-pill3", "циклы", 1490, 310, 160, C.rose),
    ...pill("c-pill4", "функции", 1010, 386, 190, C.navy),
    ...bullet("c1", "Задачи встроены в сундуки, алтари, врагов и боссов.", 1010, 505, 660),
    ...bullet("c2", "Ошибки не прерывают игру: игрок получает диагностическую подсказку.", 1010, 595, 660),
    ...bullet("c3", "Сложность растет по темам: от переменных к интеграционным сценариям.", 1010, 685, 660),
    txt("concept-note", "Так защита показывает не только интерфейс, но и педагогическую логику прототипа.", 1010, 805, 640, 70, {
      fontSize: 24,
      bold: true,
      color: C.navy,
    }),
  ]);

  s = deck.slides.add();
  root(s, [
    ...title(6, "Архитектура: Godot-клиент и FastAPI-backend", "Разделение логики позволяет независимо развивать игру, проверку кода и ИИ-подсказки.", "Архитектура"),
    img("architecture", "architecture.png", 132, 280, 840, 500, "contain"),
    ...card("arch1", 1060, 292, 590, 150, "Godot 4", "Сцены уровней, игрок, враги, коллизии, терминал, UI, пауза и события прохождения.", C.blue),
    ...card("arch2", 1060, 482, 590, 150, "FastAPI", "Генерация заданий, валидация решений, маршруты подсказок, журналирование действий.", C.red),
    ...card("arch3", 1060, 672, 590, 150, "AI-модуль", "Формирует контекстные объяснения по ошибке, теме и состоянию попытки.", C.rose),
    line("arch-flow", 238, 826, 1320, C.navy, 6),
    txt("arch-flow-text", "Игровое событие -> задание -> ввод кода -> проверка -> подсказка/успех -> изменение уровня", 300, 852, 1180, 42, {
      fontSize: 25,
      bold: true,
      color: C.navy,
      align: "center",
    }),
  ]);

  s = deck.slides.add();
  root(s, [
    ...title(7, "Практическая реализация прототипа", "На защите важно показать, что продукт работает как целостная система.", "Реализация"),
    img("gameplay", "gameplay.png", 130, 300, 760, 380, "cover"),
    img("terminal", "terminal_success.png", 1010, 300, 760, 380, "cover"),
    line("impl-line1", 130, 700, 760, C.blue, 8),
    line("impl-line2", 1010, 700, 760, C.red, 8),
    ...bullet("i1", "Уровни включают платформы, врагов, сундуки, алтари, боссы и терминальные задания.", 166, 770, 700),
    ...bullet("i2", "Проверка решения возвращает игровой эффект: открыть путь, усилить героя или завершить бой.", 1000, 770, 700),
    ...bullet("i3", "Логи фиксируют попытки, подсказки, ошибки и прохождение для дальнейшего анализа.", 1000, 850, 700),
  ]);

  s = deck.slides.add();
  root(s, [
    ...title(8, "ИИ-модуль: подсказка вместо готового ответа", "Модель получает только учебный контекст и историю попытки.", "ИИ"),
    img("ai-module", "ai_module.png", 132, 284, 780, 480, "contain"),
    ...card("ai1", 1020, 292, 640, 140, "Вход", "Тема, формулировка задания, код игрока, ошибка проверки и уровень помощи.", C.blue),
    ...card("ai2", 1020, 470, 640, 140, "Обработка", "Backend собирает промпт, ограничивает формат ответа и сохраняет событие в лог.", C.red),
    ...card("ai3", 1020, 648, 640, 140, "Выход", "Короткая подсказка, объяснение причины ошибки или рекомендация следующего действия.", C.rose),
    txt("ai-note", "Принцип проекта: ИИ снижает фрустрацию, но не забирает у студента решение.", 238, 828, 1320, 54, {
      fontSize: 30,
      bold: true,
      color: C.navy,
      align: "center",
    }),
  ]);

  s = deck.slides.add();
  root(s, [
    ...title(9, "Сценарий демонстрации на защите", "Этот слайд помогает уложить показ продукта в регламент.", "Демо"),
    ...card("demo1", 150, 300, 380, 430, "1. Уровень", "Показать движение, платформы, врага или сундук, который связан с учебной задачей.", C.blue),
    ...card("demo2", 570, 300, 380, 430, "2. Терминал", "Открыть задачу, ввести ошибочное решение и показать понятную диагностику.", C.red),
    ...card("demo3", 990, 300, 380, 430, "3. ИИ-помощь", "Запросить подсказку и подчеркнуть, что она не содержит готовый ответ.", C.rose),
    ...card("demo4", 1410, 300, 360, 430, "4. Результат", "Исправить код и показать, как игра меняет состояние уровня.", C.navy),
    txt("demo-rule", "Рекомендуемый порядок: 2 минуты на продукт, остальное - на результаты и выводы.", 244, 812, 1430, 58, {
      fontSize: 30,
      bold: true,
      color: C.navy,
      align: "center",
    }),
  ]);

  s = deck.slides.add();
  root(s, [
    ...title(10, "Пилотное тестирование: продукт дал измеримые данные", "Логи подтверждают работоспособность сценариев и показывают проблемные места.", "Тестирование"),
    ...metric("m1", 150, 300, "15", "анонимных профилей", C.red),
    ...metric("m2", 500, 300, "72", "игровые сессии", C.blue),
    ...metric("m3", 850, 300, "2536", "событий в логах", C.navy),
    ...metric("m4", 1260, 300, "573", "попытки проверки кода", C.rose),
    txt("bars-title", "Успешность по темам", 170, 520, 420, 42, {
      fontSize: 30,
      bold: true,
      color: C.navy,
    }),
    ...bar("b1", 170, 592, "Variables", 70.2, C.red),
    ...bar("b2", 170, 646, "Conditions", 52.5, C.blue),
    ...bar("b3", 170, 700, "Loops", 55.7, C.rose),
    ...bar("b4", 170, 754, "Functions", 52.1, C.navy),
    ...bar("b5", 170, 808, "Integration", 49.6, C.gray3),
    ...card("test1", 1080, 548, 620, 150, "Эффект помощи", "Без помощи: 52,1%. С подсказкой: 65,1%. С подсказкой и объяснением: 63,6%.", C.red),
    ...card("test2", 1080, 738, 620, 150, "Зона риска", "Босс-сценарии сложнее: успешность взаимодействия 44,1%, поэтому они требуют доработки баланса.", C.blue),
  ]);

  s = deck.slides.add();
  root(s, [
    ...title(11, "Выводы: цель ВКР достигнута", "Получился рабочий прототип и база для дальнейшего исследования.", "Выводы"),
    ...card("res1", 150, 300, 500, 250, "Что разработано", "Игровой клиент на Godot 4, backend на FastAPI, задания, проверка, подсказки и сбор логов.", C.blue),
    ...card("res2", 710, 300, 500, 250, "Что подтверждено", "Пилотные данные показывают, что связка «код - действие - подсказка» работает и измерима.", C.red),
    ...card("res3", 1270, 300, 500, 250, "Что ограничено", "Выборка небольшая, а баланс сложности требует дополнительного тестирования.", C.rose),
    txt("answer", "Ответ на исследовательский вопрос: платформер можно использовать как учебный интерфейс, если игровые события напрямую связаны с проверяемыми программными конструкциями, а ИИ выполняет роль контекстной поддержки.", 205, 660, 1510, 140, {
      fontSize: 31,
      bold: true,
      color: C.navy,
      align: "center",
    }),
    line("conclusion-line", 390, 850, 1140, C.red, 9),
  ]);

  s = deck.slides.add();
  root(s, [
    ...title(12, "Ключевые источники", "Слайд нужен для формального блока и вопросов комиссии.", "Источники"),
    ...card("lit1", 150, 300, 500, 250, "Обучение программированию", "Работы о сложностях начального обучения, визуализации результата и роли обратной связи.", C.blue),
    ...card("lit2", 710, 300, 500, 250, "Игровое обучение", "Источники по game-based learning, мотивации, вовлечению и проектированию учебных механик.", C.red),
    ...card("lit3", 1270, 300, 500, 250, "ИИ в образовании", "Исследования по LLM-подсказкам, scaffolding, ограничениям и риску генерации готового ответа.", C.rose),
    txt("lit-note", "На устной защите список не зачитывается: лучше связать 2-3 источника с архитектурой, подсказками и тестированием.", 238, 714, 1320, 88, {
      fontSize: 30,
      bold: true,
      color: C.navy,
      align: "center",
    }),
  ]);

  s = deck.slides.add();
  root(s, [
    box("thanks-blue", 0, 0, W, H, C.navy),
    box("thanks-red", 0, 0, 28, H, C.red),
    box("thanks-logo-bg", 74, 54, 410, 188, C.white, 0),
    img("thanks-logo", "hse:hse_template_image1.png", 96, 74, 360, 142),
    txt("thanks-title", "Спасибо за внимание", 186, 344, 1100, 92, {
      fontSize: 70,
      bold: true,
      color: C.white,
    }),
    txt("thanks-subtitle", "Готов ответить на вопросы комиссии", 190, 456, 900, 50, {
      fontSize: 32,
      color: C.pink,
      bold: true,
    }),
    txt("thanks-name", "Блинков Илья Олегович\nНИУ ВШЭ, Нижний Новгород\n2026", 190, 706, 820, 132, {
      fontSize: 28,
      color: C.white,
    }),
    img("thanks-shot", "gameplay.png", 1120, 300, 620, 350, "cover"),
    line("thanks-shot-line", 1120, 672, 620, C.red, 8),
  ], C.navy);

  return deck;
}

const deck = makeDeck();
const pptx = await PresentationFile.exportPptx(deck);
const deckPath = path.join(OUT, "Skill_Issue_HSE_defense_presentation.pptx");
await pptx.save(deckPath);

for (const slide of deck.slides.items) {
  const blob = await slide.export({ format: "png" });
  const bytes = new Uint8Array(await blob.arrayBuffer());
  fs.writeFileSync(path.join(PREV, `slide-${String(slide.index + 1).padStart(2, "0")}.png`), bytes);
}

const imported = await PresentationFile.importPptx(fs.readFileSync(deckPath));
for (const [idx, slide] of imported.slides.items.entries()) {
  const blob = await slide.export({ format: "png" });
  const bytes = new Uint8Array(await blob.arrayBuffer());
  fs.writeFileSync(path.join(PPTX_PREV, `slide-${String(idx + 1).padStart(2, "0")}.png`), bytes);
}

console.log(deckPath);
console.log(PREV);
console.log(PPTX_PREV);
