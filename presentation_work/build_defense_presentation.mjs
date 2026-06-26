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
const OUT = path.resolve("presentation_work/output");
const PREV = path.resolve("presentation_work/previews");
const ASSETS = path.resolve("presentation_work/assets");

fs.mkdirSync(OUT, { recursive: true });
fs.mkdirSync(PREV, { recursive: true });

const C = {
  paper: "#F7FAFF",
  paper2: "#EEF6FF",
  navy: "#092B63",
  blue: "#0B5CAD",
  blue2: "#1C7ED6",
  cyan: "#16B8C9",
  green: "#1B9C68",
  gold: "#D6A23A",
  ink: "#101827",
  muted: "#5F6D7E",
  pale: "#EAF3FF",
  paleCyan: "#E8FBFF",
  dark: "#08142C",
  danger: "#D94848",
};

const FONT = "Arial";

function p(asset) {
  return path.join(ASSETS, asset);
}

const imageDataUrls = new Map();

function imageDataUrl(file) {
  if (!imageDataUrls.has(file)) {
    const ext = path.extname(file).toLowerCase();
    const mime = ext === ".jpg" || ext === ".jpeg" ? "image/jpeg" : "image/png";
    const bytes = fs.readFileSync(p(file));
    imageDataUrls.set(file, `data:${mime};base64,${bytes.toString("base64")}`);
  }
  return imageDataUrls.get(file);
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
      fontSize: 30,
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

function slideRoot(slide, items, background = C.paper) {
  slide.compose(
    layers(
      { name: "slide-root", width: fill, height: fill },
      [box("background", 0, 0, W, H, background), ...items],
    ),
    { frame: { left: 0, top: 0, width: W, height: H }, baseUnit: 8 },
  );
}

function footer(n) {
  return [
    box(`footer-line-${n}`, 96, 1010, 1728, 3, C.blue),
    txt(`footer-${n}`, `ВКР: обучающая игра-платформер с интеграцией ИИ  |  ${n}`, 96, 1028, 1728, 34, {
      fontSize: 20,
      color: C.muted,
    }),
  ];
}

function title(slideNo, titleText, subtitleText = "") {
  return [
    txt(`title-${slideNo}`, titleText, 96, 64, 1260, 104, {
      fontSize: 48,
      bold: true,
      color: C.navy,
    }),
    subtitleText
      ? txt(`subtitle-${slideNo}`, subtitleText, 100, 154, 1420, 70, {
          fontSize: 24,
          color: C.muted,
        })
      : box(`subtitle-spacer-${slideNo}`, 0, 0, 1, 1, "rgba(255,255,255,0)"),
    box(`title-accent-${slideNo}`, 96, 218, 220, 8, C.cyan),
  ];
}

function card(name, left, top, width, height, heading, body, accent = C.blue) {
  return [
    box(`${name}-base`, left, top, width, height, "#FFFFFF", 20),
    box(`${name}-accent`, left, top, 12, height, accent, 20),
    txt(`${name}-heading`, heading, left + 34, top + 26, width - 58, 42, {
      fontSize: 28,
      bold: true,
      color: C.navy,
    }),
    txt(`${name}-body`, body, left + 34, top + 80, width - 58, height - 96, {
      fontSize: 23,
      color: C.ink,
    }),
  ];
}

function metric(name, left, top, width, value, label, color = C.blue) {
  return [
    txt(`${name}-value`, value, left, top, width, 70, {
      fontSize: 56,
      bold: true,
      color,
    }),
    txt(`${name}-label`, label, left, top + 72, width, 56, {
      fontSize: 22,
      color: C.muted,
    }),
  ];
}

function progressStep(name, idx, label, left, top, width, color) {
  return [
    box(`${name}-line`, left, top + 58, width, 10, color, 6),
    box(`${name}-num`, left, top, 70, 70, color, 16),
    txt(`${name}-idx`, String(idx), left + 18, top + 13, 34, 40, {
      fontSize: 32,
      bold: true,
      color: "#FFFFFF",
      align: "center",
    }),
    txt(`${name}-label`, label, left, top + 88, width, 72, {
      fontSize: 24,
      bold: true,
      color: C.navy,
    }),
  ];
}

function makeDeck() {
  const deck = Presentation.create({ slideSize: { width: W, height: H } });

  let s = deck.slides.add();
  slideRoot(s, [
    box("cover-top", 0, 0, W, 118, C.navy),
    box("cover-side", 1290, 0, 630, H, C.pale),
    box("cover-accent-1", 1290, 0, 46, H, C.cyan),
    box("cover-accent-2", 1360, 746, 440, 18, C.gold),
    txt("cover-label", "ВЫПУСКНАЯ КВАЛИФИКАЦИОННАЯ РАБОТА", 96, 38, 900, 40, {
      fontSize: 22,
      bold: true,
      color: "#FFFFFF",
      letterSpacing: 0,
    }),
    txt("cover-title", "Разработка обучающей\nигры-платформера\nс интеграцией ИИ", 96, 226, 1080, 252, {
      fontSize: 64,
      bold: true,
      color: C.navy,
    }),
    txt("cover-subtitle", "для освоения основ программирования", 100, 498, 900, 56, {
      fontSize: 34,
      color: C.blue,
      bold: true,
    }),
    txt("cover-meta", "Skill Issue · Godot 4 · Python/FastAPI · AI-подсказки", 100, 612, 930, 48, {
      fontSize: 27,
      color: C.ink,
    }),
    txt("cover-author", "Блинков Илья Олегович\nНижний Новгород, 2026", 100, 800, 760, 88, {
      fontSize: 26,
      color: C.muted,
    }),
    img("cover-gameplay", "terminal_success.png", 1322, 164, 520, 310, "cover"),
    img("cover-architecture", "architecture.png", 1378, 520, 430, 322, "contain"),
  ]);

  s = deck.slides.add();
  slideRoot(s, [
    ...title(2, "Актуальность: почему нужен такой формат", "Новичку важно видеть связь между кодом и результатом сразу, а не после абстрактной лекции."),
    ...card("problem-1", 112, 280, 500, 250, "Абстрактность", "Переменные, условия, циклы и функции сложно понять без видимого действия и контекста.", C.blue),
    ...card("problem-2", 710, 280, 500, 250, "Ошибки как тупик", "Сообщение об ошибке часто не объясняет, что именно исправить и почему решение не работает.", C.danger),
    ...card("problem-3", 1308, 280, 500, 250, "Низкая мотивация", "Однообразные упражнения быстро превращают обучение в механический ввод кода.", C.gold),
    box("hypothesis-bg", 208, 650, 1504, 190, C.paleCyan, 28),
    txt("hypothesis-title", "Гипотеза решения", 252, 684, 380, 44, { fontSize: 32, bold: true, color: C.navy }),
    txt("hypothesis-text", "Игровая среда + AI-подсказки + адаптация сложности дают новичку практику, обратную связь и ощущение прогресса в одном сценарии.", 252, 742, 1388, 72, { fontSize: 30, color: C.ink }),
    ...footer(2),
  ]);

  s = deck.slides.add();
  slideRoot(s, [
    ...title(3, "Цель, объект и задачи исследования", "На защите этот слайд фиксирует рамки работы и показывает, что разработка не оторвана от исследования."),
    box("goal-bg", 96, 270, 780, 330, "#FFFFFF", 24),
    txt("goal-kicker", "Цель", 136, 310, 180, 42, { fontSize: 28, bold: true, color: C.cyan }),
    txt("goal-text", "Разработать игру-платформер для обучения основам программирования с поддержкой ИИ в реальном времени.", 136, 370, 660, 128, { fontSize: 34, bold: true, color: C.navy }),
    txt("object-text", "Объект: процесс обучения основам программирования.\nПредмет: игровой платформер и AI-модуль персонализированной помощи.", 136, 520, 660, 70, { fontSize: 22, color: C.muted }),
    ...progressStep("task-1", 1, "анализ аналогов", 980, 278, 300, C.blue),
    ...progressStep("task-2", 2, "концепция продукта", 1280, 278, 300, C.cyan),
    ...progressStep("task-3", 3, "архитектура AI", 980, 500, 300, C.green),
    ...progressStep("task-4", 4, "интеграция LLM", 1280, 500, 300, C.gold),
    ...progressStep("task-5", 5, "пилотное тестирование", 980, 722, 600, C.navy),
    ...footer(3),
  ]);

  s = deck.slides.add();
  slideRoot(s, [
    ...title(4, "Теоретическая база и анализ аналогов", "Что взято из теории: игровые механики должны быть связаны с учебной целью, а подсказки не должны заменять решение."),
    ...card("theory-1", 96, 260, 520, 220, "Игровое обучение", "Прогресс, цели, награды и мгновенный результат помогают удерживать внимание.", C.blue),
    ...card("theory-2", 700, 260, 520, 220, "AI-поддержка", "Подсказки и объяснения должны быть контекстными, но не превращаться в готовый ответ.", C.cyan),
    ...card("theory-3", 1304, 260, 520, 220, "Пробел аналогов", "CodeCombat, CodinGame, CheckiO, Scratch, Blockly Games и Code.org закрывают разные части задачи, но не всю систему целиком.", C.gold),
    box("analogs-table-bg", 180, 590, 1560, 280, "#FFFFFF", 22),
    txt("analogs-head", "Вывод из анализа", 230, 628, 360, 40, { fontSize: 31, bold: true, color: C.navy }),
    txt("analogs-text", "Нужен прототип, где код влияет на прохождение уровня: врагов, сундуки, алтари и босс-сцены. AI здесь выступает не отдельным чат-ботом, а частью учебной логики.", 230, 696, 1410, 104, { fontSize: 30, color: C.ink }),
    ...footer(4),
  ]);

  s = deck.slides.add();
  slideRoot(s, [
    ...title(5, "Концепция продукта: обучение через игровой цикл", "Пользователь не решает задачи отдельно от игры: задание появляется внутри действия уровня."),
    img("game-loop", "game_loop.png", 94, 255, 980, 660, "contain"),
    box("concept-note", 1120, 292, 650, 480, "#FFFFFF", 24),
    txt("concept-note-title", "Ключевая идея", 1160, 330, 560, 44, { fontSize: 34, bold: true, color: C.navy }),
    txt("concept-note-body", "Каждая программная конструкция получает игровой смысл:\n\nпеременная → параметр боя\nусловие → выбор действия\nцикл → повторяемая тактика\nфункция → переиспользуемый прием\nинтеграция → комплексное решение", 1160, 398, 560, 300, { fontSize: 29, color: C.ink }),
    box("concept-accent", 1120, 805, 650, 18, C.cyan, 10),
    ...footer(5),
  ]);

  s = deck.slides.add();
  slideRoot(s, [
    ...title(6, "Архитектура системы", "Разделение на Godot-клиент и Python/FastAPI backend позволяет независимо развивать игру и проверку заданий."),
    img("architecture", "architecture.png", 80, 236, 1040, 700, "contain"),
    ...card("arch-1", 1190, 280, 590, 170, "Godot 4", "сцены уровней, персонаж, враги, Combat Terminal, HUD, меню, босс-комнаты", C.blue),
    ...card("arch-2", 1190, 500, 590, 170, "FastAPI", "генерация заданий, проверка кода, подсказки, логирование попыток", C.cyan),
    ...card("arch-3", 1190, 720, 590, 170, "Данные", "логи прохождения и метрики используются для адаптации сложности", C.green),
    ...footer(6),
  ]);

  s = deck.slides.add();
  slideRoot(s, [
    ...title(7, "Что реализовано в коде", "Практическая часть построена как связка игровых сцен, API-клиента и серверных сервисов."),
    box("code-left", 112, 274, 780, 560, "#FFFFFF", 22),
    txt("code-left-title", "Godot-клиент", 152, 314, 600, 42, { fontSize: 34, bold: true, color: C.blue }),
    txt("code-left-body", "game.gd — общий игровой поток\nlevel_layout_generator.gd — генерация уровней\nenemy_encounter.gd / boss_encounter.gd — враги и боссы\ncombat_terminal.gd — ввод кода, подсказки, таймер\ncode_api_client.gd — HTTP-запросы к backend", 152, 386, 690, 300, { fontSize: 27, color: C.ink }),
    box("code-right", 1028, 274, 780, 560, "#FFFFFF", 22),
    txt("code-right-title", "Backend-сервис", 1068, 314, 600, 42, { fontSize: 34, bold: true, color: C.cyan }),
    txt("code-right-body", "main.py — API-эндпоинты\nvalidator.py — синтаксис, тема, семантика\ntasks.py — генерация заданий и fallback\nllm.py — обращение к LLM и обработка ответа\nlogger.py — сбор логов и экспорт XLSX", 1068, 386, 690, 300, { fontSize: 27, color: C.ink }),
    box("pipeline", 268, 780, 1384, 72, C.paleCyan, 18),
    txt("pipeline-text", "Combat Terminal → /tasks/generate → /validate или /hints → результат → изменение состояния игры", 310, 800, 1300, 34, { fontSize: 28, bold: true, color: C.navy }),
    ...footer(7),
  ]);

  s = deck.slides.add();
  slideRoot(s, [
    ...title(8, "Учебная структура уровней", "Уровни идут от простых конструкций к комбинированным задачам."),
    ...progressStep("lvl-1", 1, "Variables\nприсваивание значений", 118, 300, 320, C.blue),
    ...progressStep("lvl-2", 2, "If / Else\nветвление действий", 462, 300, 320, C.cyan),
    ...progressStep("lvl-3", 3, "Loops\nповторение действий", 806, 300, 320, C.green),
    ...progressStep("lvl-4", 4, "Functions\nпереиспользование логики", 1150, 300, 320, C.gold),
    ...progressStep("lvl-5", 5, "Integration\nкомбинация тем", 1494, 300, 320, C.navy),
    box("interactions-bg", 208, 640, 1504, 210, "#FFFFFF", 26),
    txt("interactions-title", "Типы учебных взаимодействий", 252, 674, 500, 44, { fontSize: 32, bold: true, color: C.navy }),
    txt("interactions-body", "combat — урон врагу · chest — открытие награды · altar — настройка оружия · boss — итоговая проверка темы", 252, 742, 1360, 54, { fontSize: 31, color: C.ink }),
    ...footer(8),
  ]);

  s = deck.slides.add();
  slideRoot(s, [
    ...title(9, "AI-модуль: подсказки, проверка и адаптация", "В текущем прототипе AI-логика гибридная: правила и fallback работают всегда, LLM подключается при наличии ключа."),
    img("ai-module", "ai_module.png", 72, 244, 1010, 690, "contain"),
    ...card("ai-1", 1160, 278, 590, 150, "Проверка", "AST-разбор, синтаксис, тема уровня, ключевые понятия и игровые эффекты", C.blue),
    ...card("ai-2", 1160, 470, 590, 150, "Подсказки", "помогают найти ошибку, но не дают финальное решение", C.cyan),
    ...card("ai-3", 1160, 662, 590, 150, "Адаптация", "успех, время и ошибки влияют на рекомендуемую сложность", C.green),
    ...footer(9),
  ]);

  s = deck.slides.add();
  slideRoot(s, [
    ...title(10, "Демонстрация пользовательского сценария", "На защите лучше показать полный путь: уровень → терминал → проверка → изменение игрового состояния."),
    img("demo-1", "gameplay.png", 96, 266, 540, 320, "cover"),
    img("demo-2", "terminal_task.png", 690, 266, 540, 320, "cover"),
    img("demo-3", "terminal_success.png", 1284, 266, 540, 320, "cover"),
    txt("demo-label-1", "1. Прохождение уровня", 118, 626, 500, 42, { fontSize: 28, bold: true, color: C.navy }),
    txt("demo-label-2", "2. Combat Terminal", 712, 626, 500, 42, { fontSize: 28, bold: true, color: C.navy }),
    txt("demo-label-3", "3. Успех влияет на игру", 1306, 626, 500, 42, { fontSize: 28, bold: true, color: C.navy }),
    box("demo-note", 238, 760, 1444, 104, C.paleCyan, 22),
    txt("demo-note-text", "Главная демонстрационная мысль: код не просто проверяется, а становится действием в игровом мире.", 282, 790, 1360, 42, { fontSize: 31, bold: true, color: C.navy }),
    ...footer(10),
  ]);

  s = deck.slides.add();
  const bars = [
    ["Переменные", 70.2, C.blue],
    ["Условия", 52.5, C.cyan],
    ["Циклы", 55.7, C.green],
    ["Функции", 52.1, C.gold],
    ["Интеграция", 49.6, C.navy],
  ];
  const barItems = [];
  bars.forEach(([label, value, color], i) => {
    const y = 500 + i * 64;
    barItems.push(txt(`bar-label-${i}`, label, 870, y - 8, 220, 32, { fontSize: 22, color: C.ink }));
    barItems.push(box(`bar-bg-${i}`, 1110, y, 430, 28, "#DDE8F7", 8));
    barItems.push(box(`bar-${i}`, 1110, y, 430 * value / 80, 28, color, 8));
    barItems.push(txt(`bar-value-${i}`, `${value}%`, 1562, y - 5, 120, 30, { fontSize: 22, bold: true, color: C.navy }));
  });
  slideRoot(s, [
    ...title(11, "Результаты тестирования", "Проверка выполнялась по логам тестовых прохождений: важны не только запуск игры, но и поведение игрока в заданиях."),
    ...metric("m1", 118, 270, 300, "15", "анонимных профилей логов", C.blue),
    ...metric("m2", 442, 270, 300, "72", "игровые сессии", C.cyan),
    ...metric("m3", 118, 430, 300, "573", "попытки проверки кода", C.green),
    ...metric("m4", 442, 430, 300, "317", "успешные проверки", C.gold),
    box("test-chart-bg", 820, 270, 920, 520, "#FFFFFF", 24),
    txt("test-chart-title", "Успешность по темам", 870, 308, 520, 40, { fontSize: 32, bold: true, color: C.navy }),
    txt("test-chart-note", "Самые сложные зоны: интеграция тем и босс-задания.", 870, 360, 740, 36, { fontSize: 23, color: C.muted }),
    ...barItems,
    box("help-bg", 118, 660, 620, 150, C.paleCyan, 22),
    txt("help-title", "Эффект помощи", 154, 694, 300, 38, { fontSize: 30, bold: true, color: C.navy }),
    txt("help-text", "Успешность без помощи: 52,1%.\nС подсказкой: 65,1%.", 154, 746, 520, 48, { fontSize: 27, color: C.ink }),
    ...footer(11),
  ]);

  s = deck.slides.add();
  slideRoot(s, [
    ...title(12, "Итоги работы", "Цель в основном достигнута: создан рабочий прототип и проверена логика обучения через игровой сценарий."),
    ...card("result-1", 110, 285, 520, 260, "Реализовано", "Godot-прототип, уровни, Combat Terminal, враги, боссы, FastAPI backend, проверка, подсказки и логирование.", C.green),
    ...card("result-2", 700, 285, 520, 260, "Практическая значимость", "Проект можно использовать как основу для дальнейшего образовательного продукта и пилотных исследований.", C.blue),
    ...card("result-3", 1290, 285, 520, 260, "Ограничения", "Текущая версия является прототипом: нужны расширенная апробация, улучшение семантической проверки и UX-полировка.", C.gold),
    box("next-bg", 220, 680, 1480, 146, "#FFFFFF", 24),
    txt("next-title", "Направления развития", 260, 708, 420, 38, { fontSize: 30, bold: true, color: C.navy }),
    txt("next-text", "расширить набор заданий · подключить более устойчивую LLM-интеграцию · провести тестирование на учебной группе · улучшить аналитику прогресса", 260, 760, 1360, 42, { fontSize: 27, color: C.ink }),
    ...footer(12),
  ]);

  s = deck.slides.add();
  slideRoot(s, [
    ...title(13, "Резерв: возможные вопросы комиссии", "Этот слайд можно держать в конце как подсказку для Q&A, но не обязательно показывать во время доклада."),
    ...card("q1", 96, 274, 540, 210, "Почему игра, а не обычный тренажер?", "Потому что игровой мир дает мгновенную визуальную связь между кодом и результатом.", C.blue),
    ...card("q2", 690, 274, 540, 210, "Где здесь ИИ?", "В генерации/оценке заданий, подсказках, семантической проверке и адаптации сложности.", C.cyan),
    ...card("q3", 1284, 274, 540, 210, "Что будет без LLM?", "Fallback-правила сохраняют работоспособность терминала и демонстрации.", C.green),
    ...card("q4", 96, 560, 540, 210, "Как проверяется код?", "Сначала синтаксис и AST, затем тематические правила, ключевые понятия и игровой контекст.", C.gold),
    ...card("q5", 690, 560, 540, 210, "Почему FastAPI отдельно?", "Так проще развивать проверку и AI-модуль независимо от Godot-сцен.", C.blue),
    ...card("q6", 1284, 560, 540, 210, "Что доказывает тестирование?", "Оно показывает работоспособность сценариев и дает первичные метрики поведения игроков.", C.danger),
    ...footer(13),
  ]);

  s = deck.slides.add();
  slideRoot(s, [
    ...title(14, "Что повторить перед защитой", "Самое важное - уверенно объяснить границы прототипа и связь между педагогической идеей и кодом."),
    box("study-bg", 162, 280, 1596, 560, "#FFFFFF", 24),
    txt("study-list", "1. Разница между игровым обучением и геймификацией.\n2. Почему игровые действия напрямую связаны с учебными конструкциями.\n3. Архитектура: Godot-клиент, FastAPI-backend, API-запросы.\n4. Как работает проверка кода: AST, правила, ключевые понятия, fallback.\n5. Как формируются подсказки и почему они не должны давать готовый ответ.\n6. Что означают метрики тестирования: успешность, время, подсказки, ошибки.\n7. Ограничения работы и план развития после прототипа.", 220, 330, 1480, 420, {
      fontSize: 31,
      color: C.ink,
    }),
    box("final-line", 220, 802, 1480, 12, C.cyan, 8),
    ...footer(14),
  ]);

  return deck;
}

const deck = makeDeck();
const pptx = await PresentationFile.exportPptx(deck);
const deckPath = path.join(OUT, "Skill_Issue_defense_presentation.pptx");
await pptx.save(deckPath);

for (const slide of deck.slides.items) {
  const blob = await slide.export({ format: "png" });
  const bytes = new Uint8Array(await blob.arrayBuffer());
  fs.writeFileSync(path.join(PREV, `slide-${String(slide.index + 1).padStart(2, "0")}.png`), bytes);
}

const layoutReport = [];
for (const slide of deck.slides.items) {
  const layout = await slide.export({ format: "layout" });
  layoutReport.push({ slide: slide.index + 1, layout });
}
fs.writeFileSync(path.join(OUT, "layout-report.json"), JSON.stringify(layoutReport, null, 2), "utf-8");

console.log(deckPath);
console.log(PREV);
