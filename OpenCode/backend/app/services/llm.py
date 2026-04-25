from __future__ import annotations

import json
import random
import re
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from app.models import Difficulty, InteractionType, TaskGenerationResponse
from app.settings import get_settings


SYSTEM_PROMPT = (
    "You are the Skill Issue teaching assistant. Help beginner programming students inside a game. "
    "Be encouraging, precise, and fast. Never give a full final solution. "
    "Give hints that are obvious enough to unblock the student, but still require them to write the answer. "
    "Respect the syntax and structure of the target language. "
    "Auto-complete code only when tutorial mode is explicitly enabled."
)

RNG = random.SystemRandom()

THEME_VARIATION_PACKS = {
    "variables": {
        "gameplay_focuses": [
            "damage and attack tempo",
            "hp and shield durability",
            "movement speed and dodge timing",
            "guard window and recovery timing",
        ],
        "explanation_angles": [
            "explain how one variable stores one gameplay value",
            "explain how changing a number changes the next combat exchange",
            "explain why readable variable names help the player reason about stats",
        ],
        "example_styles": [
            "use two short numeric assignments",
            "use three short stat assignments",
            "use one simple combat-stat setup",
        ],
        "subtopics": [
            "numeric variables for damage, hp, speed, or shield",
            "string or text values used to choose a simple combat mode",
            "boolean values for states like guarding or ready",
            "reassignment where a stat changes between one step and the next",
            "simple operators like +=, -=, or *= when changing a stat",
        ],
        "structure_focuses": [
            "two clean assignments",
            "three compact assignments",
            "one short stat setup with reassignment",
        ],
    },
    "conditions": {
        "gameplay_focuses": [
            "close-versus-far attack choice",
            "block-versus-strike decision making",
            "safe-versus-risky reaction timing",
            "boss-open-versus-boss-guarded pressure",
        ],
        "explanation_angles": [
            "explain true and false branches in plain beginner language",
            "explain how one condition can control one tactical choice",
            "explain how if/else avoids guessing in combat",
        ],
        "example_styles": [
            "show one clean if/else with one action result",
            "show one branch that chooses between two combat actions",
            "show one readable condition with short branches",
        ],
        "subtopics": [
            "comparison operators like <, >, ==, or !=",
            "boolean checks for combat states",
            "if/else flow for choosing between two actions",
            "elif as an optional middle branch when it stays readable",
            "combining two simple checks with and/or only when necessary",
        ],
        "structure_focuses": [
            "one direct if/else branch",
            "one readable combat branch with one action per path",
            "one short branch with a possible elif when needed",
        ],
    },
    "loops": {
        "gameplay_focuses": [
            "repeating a volley",
            "repeating a shield pulse",
            "repeating a short punish pattern",
            "repeating a guard or dash rhythm",
        ],
        "explanation_angles": [
            "explain repetition with a clear stopping rule",
            "explain how a loop repeats one small useful action",
            "explain why loops need control and should not run forever",
        ],
        "example_styles": [
            "show one short for loop",
            "show one compact repeated combat action",
            "show one loop with a clear repeat count",
        ],
        "subtopics": [
            "for loops with range for counted repeats",
            "while loops with a clear stop condition",
            "small loop bodies that repeat one useful combat action",
            "counters or repeat counts that stay readable",
            "avoiding endless loops by keeping the stop rule clear",
        ],
        "structure_focuses": [
            "one short for loop",
            "one controlled while loop",
            "one compact repeat pattern with a clear stop rule",
        ],
    },
    "functions": {
        "gameplay_focuses": [
            "reusable combo logic",
            "a reusable shield or heal helper",
            "a reusable punish routine",
            "a reusable forge-tuning step",
        ],
        "explanation_angles": [
            "explain how a function packages a tactic under one name",
            "explain why reusable logic is better than copying lines",
            "explain define first and call after in beginner terms",
        ],
        "example_styles": [
            "show one tiny helper function and one call",
            "show one short function with one simple action",
            "show one reusable combat helper",
        ],
        "subtopics": [
            "defining one function before calling it",
            "parameters for one small reusable combat value",
            "return values when they help keep the snippet clean",
            "local variables inside a function",
            "reusing one helper instead of copying lines",
        ],
        "structure_focuses": [
            "one tiny helper function and one call",
            "one short function with one parameter",
            "one helper with a clear return or side effect",
        ],
    },
    "integration": {
        "gameplay_focuses": [
            "mixing stat setup with a tactical decision",
            "mixing a branch with repeated pressure",
            "mixing a helper function with a combat condition",
            "mixing two or three earlier tools into one compact tactic",
        ],
        "explanation_angles": [
            "explain that integration means combining earlier tools with purpose",
            "explain how several simple constructs can form one tactic",
            "explain why the combined snippet must still stay readable",
        ],
        "example_styles": [
            "show a minimal combination of two constructs",
            "show a compact mixed tactic without over-explaining it",
            "show a small readable multi-part tactic",
        ],
        "subtopics": [
            "combining variables with a condition",
            "combining a loop with a stat change",
            "combining a function with a branch",
            "keeping a mixed tactic readable and compact",
            "choosing only the constructs that truly help the gameplay effect",
        ],
        "structure_focuses": [
            "a compact two-part tactic",
            "a readable mixed snippet with two constructs",
            "a short multi-step tactic that still stays simple",
        ],
    },
}

HINT_STYLE_PACKS = [
    {
        "tone": "coach-like and direct",
        "format": "start each hint with a short action verb",
        "avoidance": "avoid abstract theory and focus on the next practical fix",
    },
    {
        "tone": "encouraging and concrete",
        "format": "make each hint a short sentence",
        "avoidance": "avoid long explanations and avoid final code",
    },
    {
        "tone": "diagnostic and fast",
        "format": "point to one mistake and one next step",
        "avoidance": "avoid extra filler and avoid unrelated topics",
    },
]

TASK_WRITING_PACKS = [
    {
        "task_shape": "a short combat prep challenge",
        "task_voice": "clear and game-like",
        "explanation_shape": "one compact teaching paragraph plus short rules",
    },
    {
        "task_shape": "a practical arena problem",
        "task_voice": "simple and beginner-friendly",
        "explanation_shape": "one focused teaching paragraph plus short rules",
    },
    {
        "task_shape": "a mechanic-tuning exercise",
        "task_voice": "short, vivid, and action-oriented",
        "explanation_shape": "one plain-language explanation plus short rules",
    },
]

_HINT_CACHE: dict[str, tuple[float, list[str]]] = {}
_RATE_LIMIT_UNTIL_MONOTONIC: float = 0.0
_RATE_LIMIT_REASON: str = ""
_RATE_LIMIT_IS_TEMPORARY: bool = True


def generate_llm_hints(
    *,
    interaction_type: InteractionType,
    level_theme: str,
    difficulty: Difficulty,
    language: str,
    encounter_name: str,
    encounter_style: str,
    gameplay_context: str,
    structure_focus: str,
    boss_mechanic: str,
    task_prompt: str,
    keywords: list[str],
    validation_targets: list[str],
    code: str,
    errors: list[str],
) -> list[str]:
    settings = get_settings()
    if not settings.llm_enabled or not settings.llm_api_key:
        return []

    cache_key: str = _build_hint_cache_key(
        interaction_type=interaction_type,
        level_theme=level_theme,
        difficulty=difficulty,
        language=language,
        encounter_name=encounter_name,
        encounter_style=encounter_style,
        gameplay_context=gameplay_context,
        structure_focus=structure_focus,
        boss_mechanic=boss_mechanic,
        task_prompt=task_prompt,
        keywords=keywords,
        validation_targets=validation_targets,
        code=code,
        errors=errors,
        max_hints=settings.llm_max_hints,
    )
    cached_hints: list[str] | None = _get_cached_hints(cache_key, settings.llm_hint_cache_ttl_seconds)
    if cached_hints is not None:
        return cached_hints

    rate_limit_detail: str | None = _get_rate_limit_detail()
    if rate_limit_detail is not None:
        return []

    user_prompt = _build_hint_prompt(
        interaction_type=interaction_type,
        level_theme=level_theme,
        difficulty=difficulty,
        language=language,
        encounter_name=encounter_name,
        encounter_style=encounter_style,
        gameplay_context=gameplay_context,
        structure_focus=structure_focus,
        boss_mechanic=boss_mechanic,
        task_prompt=task_prompt,
        keywords=keywords,
        validation_targets=validation_targets,
        code=code,
        errors=errors,
        max_hints=settings.llm_max_hints,
    )
    try:
        response_text, _used_model = _call_responses_api_with_model_fallback(
            api_url=settings.llm_api_url,
            api_key=settings.llm_api_key,
            models=_response_attempt_models(),
            timeout_seconds=settings.llm_timeout_seconds,
            user_prompt=user_prompt,
            temperature=0.75,
        )
    except HTTPError as exc:
        if exc.code == 429:
            _activate_rate_limit_cooldown(exc, settings.llm_rate_limit_cooldown_seconds)
        return []
    except (URLError, TimeoutError, OSError, ValueError):
        return []
    hints: list[str] = _parse_hint_lines(response_text, settings.llm_max_hints)
    _store_cached_hints(cache_key, hints)
    return hints


def generate_llm_task(
    *,
    interaction_type: InteractionType,
    level_theme: str,
    difficulty: Difficulty,
    language: str,
    encounter_name: str,
    encounter_style: str,
    gameplay_context: str,
    structure_focus: str,
    boss_mechanic: str,
    tutorial_mode: bool,
    adaptation_reason: str,
) -> TaskGenerationResponse | None:
    task, _reason = generate_llm_task_with_detail(
        interaction_type=interaction_type,
        level_theme=level_theme,
        difficulty=difficulty,
        language=language,
        encounter_name=encounter_name,
        encounter_style=encounter_style,
        gameplay_context=gameplay_context,
        structure_focus=structure_focus,
        boss_mechanic=boss_mechanic,
        tutorial_mode=tutorial_mode,
        adaptation_reason=adaptation_reason,
    )
    return task


def evaluate_llm_submission_with_detail(
    *,
    interaction_type: InteractionType,
    level_theme: str,
    difficulty: Difficulty,
    language: str,
    encounter_name: str,
    encounter_style: str,
    gameplay_context: str,
    structure_focus: str,
    boss_mechanic: str,
    task_prompt: str,
    keywords: list[str],
    syntax_rules: list[str],
    code: str,
) -> tuple[dict | None, str]:
    settings = get_settings()
    if not settings.llm_enabled:
        return None, "LLM disabled in settings"
    if not settings.llm_api_key:
        return None, "API key missing"

    rate_limit_detail: str | None = _get_rate_limit_detail()
    if rate_limit_detail is not None:
        return None, rate_limit_detail

    last_detail: str = "AI semantic validation failed"
    for attempt_index in range(2):
        user_prompt = _build_validation_prompt(
            interaction_type=interaction_type,
            level_theme=level_theme,
            difficulty=difficulty,
            language=language,
            encounter_name=encounter_name,
            encounter_style=encounter_style,
            gameplay_context=gameplay_context,
            structure_focus=structure_focus,
            boss_mechanic=boss_mechanic,
            task_prompt=task_prompt,
            keywords=keywords,
            syntax_rules=syntax_rules,
            code=code,
            strict_response_mode=attempt_index > 0,
        )
        try:
            response_text, used_model = _call_responses_api_with_model_fallback(
                api_url=settings.llm_api_url,
                api_key=settings.llm_api_key,
                models=_response_attempt_models(),
                timeout_seconds=settings.llm_timeout_seconds,
                user_prompt=user_prompt,
                max_output_tokens=320,
                temperature=0.15,
            )
        except HTTPError as exc:
            if exc.code == 429:
                _activate_rate_limit_cooldown(exc, settings.llm_rate_limit_cooldown_seconds)
                return None, _get_rate_limit_detail() or "HTTP 429 from AI provider"
            if exc.code == 400:
                error_detail: str = _extract_http_error_detail(exc)
                if error_detail:
                    return None, "HTTP 400: %s" % _summarize_provider_error(error_detail)
            if exc.code == 403:
                error_detail = _extract_http_error_detail(exc)
                if error_detail:
                    return None, "HTTP 403: %s" % _summarize_provider_error(error_detail)
            return None, "HTTP %s from AI provider" % exc.code
        except URLError:
            return None, "Network error while contacting AI provider"
        except TimeoutError:
            return None, "AI request timed out"
        except OSError:
            return None, "Local connection error while contacting AI provider"
        except ValueError:
            return None, "AI response parsing failed"
        verdict_payload: dict = _extract_validation_payload(response_text)
        if not _is_valid_validation_payload(verdict_payload):
            last_detail = "AI validation returned incomplete payload on attempt %s" % (attempt_index + 1)
            continue
        verdict_payload["generation_detail"] = "Live AI semantic validation (%s, attempt %s)" % (used_model, attempt_index + 1)
        return verdict_payload, str(verdict_payload["generation_detail"])
    return None, "%s after repeated retries" % last_detail


def generate_llm_task_with_detail(
    *,
    interaction_type: InteractionType,
    level_theme: str,
    difficulty: Difficulty,
    language: str,
    encounter_name: str,
    encounter_style: str,
    gameplay_context: str,
    structure_focus: str,
    boss_mechanic: str,
    tutorial_mode: bool,
    adaptation_reason: str,
) -> tuple[TaskGenerationResponse | None, str]:
    settings = get_settings()
    if not settings.llm_enabled:
        return None, "LLM disabled in settings"
    if not settings.llm_api_key:
        return None, "API key missing"

    rate_limit_detail: str | None = _get_rate_limit_detail()
    if rate_limit_detail is not None:
        return None, rate_limit_detail

    last_generation_detail: str = "AI returned invalid structured task"
    for attempt_index in range(3):
        user_prompt = _build_task_prompt(
            interaction_type=interaction_type,
            level_theme=level_theme,
            difficulty=difficulty,
            language=language,
            encounter_name=encounter_name,
            encounter_style=encounter_style,
            gameplay_context=gameplay_context,
            structure_focus=structure_focus,
            boss_mechanic=boss_mechanic,
            tutorial_mode=tutorial_mode,
            adaptation_reason=adaptation_reason,
            strict_response_mode=attempt_index > 0,
        )
        try:
            response_text, used_model = _call_responses_api_with_model_fallback(
                api_url=settings.llm_api_url,
                api_key=settings.llm_api_key,
                models=_response_attempt_models(),
                timeout_seconds=settings.llm_timeout_seconds,
                user_prompt=user_prompt,
                max_output_tokens=800,
                temperature=0.35 if attempt_index == 0 else 0.2,
            )
        except HTTPError as exc:
            if exc.code == 429:
                _activate_rate_limit_cooldown(exc, settings.llm_rate_limit_cooldown_seconds)
                return None, _get_rate_limit_detail() or "HTTP 429 from AI provider"
            if exc.code == 400:
                error_detail: str = _extract_http_error_detail(exc)
                if error_detail:
                    return None, "HTTP 400: %s" % _summarize_provider_error(error_detail)
            if exc.code == 403:
                error_detail = _extract_http_error_detail(exc)
                if error_detail:
                    return None, "HTTP 403: %s" % _summarize_provider_error(error_detail)
            return None, "HTTP %s from AI provider" % exc.code
        except URLError:
            return None, "Network error while contacting AI provider"
        except TimeoutError:
            return None, "AI request timed out"
        except OSError:
            return None, "Local connection error while contacting AI provider"
        except ValueError:
            return None, "AI response parsing failed"
        try:
            task_payload: dict = _extract_task_payload(response_text)
        except ValueError:
            last_generation_detail = "AI returned invalid structured task on attempt %s" % (attempt_index + 1)
            continue
        if not _is_valid_task_payload(task_payload):
            last_generation_detail = "AI returned incomplete task payload on attempt %s" % (attempt_index + 1)
            continue
        response = TaskGenerationResponse(
            interaction_type=interaction_type,
            level_theme=level_theme,
            difficulty=difficulty,
            language=language,
            generation_source="ai",
            generation_detail="Live AI generation (%s, attempt %s)" % (used_model, attempt_index + 1),
            title=str(task_payload.get("title", "Code task")).strip() or "Code task",
            prompt=str(task_payload.get("prompt", "")).strip() or "Write a short snippet for the current mechanic.",
            gameplay_effect=str(task_payload.get("gameplay_effect", "")).strip() or "A correct solution improves the current combat state.",
            syntax_rules=_normalize_string_list(task_payload.get("syntax_rules", [])),
            explanation_title=str(task_payload.get("explanation_title", level_theme.capitalize())).strip() or level_theme.capitalize(),
            explanation_body=str(task_payload.get("explanation_body", "")).strip(),
            explanation_rules=_normalize_string_list(task_payload.get("explanation_rules", [])),
            explanation_prompt=str(task_payload.get("explanation_prompt", "")).strip(),
            keywords=_normalize_string_list(task_payload.get("keywords", [])),
            validation_targets=_normalize_string_list(task_payload.get("validation_targets", [])),
            example_code=str(task_payload.get("example_code", "")).strip(),
            adaptation_reason=adaptation_reason,
            fallback_hints=_build_task_aligned_hints(task_payload, interaction_type),
        )
        return response, "Live AI generation (%s, attempt %s)" % (used_model, attempt_index + 1)
    return None, "%s after repeated retries" % last_generation_detail


def _build_task_aligned_hints(task_payload: dict, interaction_type: InteractionType) -> list[str]:
    targets: list[str] = _normalize_string_list(task_payload.get("validation_targets", []))
    if not targets:
        targets = _normalize_string_list(task_payload.get("keywords", []))
    focus: str = ", ".join(targets[:3]) if targets else "the task concepts"
    prompt: str = str(task_payload.get("prompt", "")).strip()
    if interaction_type == "altar":
        return [
            "Map the forge task to code concepts around %s." % focus,
            "Keep every line connected to the same weapon setup instead of writing generic combat code.",
        ]
    return [
        "Map the task wording to code concepts around %s." % focus,
        "Keep the snippet focused on the exact prompt: %s" % prompt[:120],
    ]


def _build_hint_prompt(
    *,
    interaction_type: InteractionType,
    level_theme: str,
    difficulty: Difficulty,
    language: str,
    encounter_name: str,
    encounter_style: str,
    gameplay_context: str,
    structure_focus: str,
    boss_mechanic: str,
    task_prompt: str,
    keywords: list[str],
    validation_targets: list[str],
    code: str,
    errors: list[str],
    max_hints: int,
) -> str:
    error_block: str = "\n".join(f"- {item}" for item in errors) if errors else "- no parser or validator errors yet"
    normalized_code: str = code.strip() or "<empty>"
    language_guidance: str = _language_guidance(language)
    theme_pack: dict[str, list[str]] = _theme_variation_pack(level_theme)
    hint_style: dict[str, str] = RNG.choice(HINT_STYLE_PACKS)
    gameplay_focus: str = RNG.choice(theme_pack["gameplay_focuses"])
    explanation_angle: str = RNG.choice(theme_pack["explanation_angles"])
    subtopic_focus: str = RNG.choice(theme_pack["subtopics"])
    structure_target: str = structure_focus.strip() if structure_focus.strip() else RNG.choice(theme_pack["structure_focuses"])
    variant_tag: str = _random_variant_tag()
    prompt_focus: str = task_prompt.strip() if task_prompt.strip() else "no exact task text provided"
    keyword_focus: str = ", ".join(keywords[:6]) if keywords else "no explicit task keywords"
    target_focus: str = ", ".join(validation_targets[:6]) if validation_targets else "no explicit validation targets"
    altar_hint_block: str = (
        "This is an altar interaction: every hint must be about forging or tuning a weapon setup. "
        "Keep hints aligned with the same weapon concepts requested by the task, such as blade damage, ranged damage, guard timing, reach, speed, shield, or recovery. "
        "Do not give generic combat advice that is not connected to the altar task. "
        if interaction_type == "altar"
        else ""
    )
    boss_hint_block: str = (
        "This is a boss interaction: every hint must stay tied to the exact boss task, boss mechanic, and current theme. "
        "Do not drift into generic enemy hints or altar wording. "
        if interaction_type == "boss"
        else ""
    )
    return (
        f"Variation tag: {variant_tag}\n"
        f"Programming language: {language}\n"
        f"Language rules: {language_guidance}\n"
        f"Interaction type: {interaction_type}\n"
        f"Programming theme: {level_theme}\n"
        f"Difficulty: {difficulty}\n"
        f"Encounter name: {encounter_name if encounter_name else 'unspecified encounter'}\n"
        f"Encounter style: {encounter_style if encounter_style else 'generic'}\n"
        f"Boss mechanic: {boss_mechanic if boss_mechanic else 'not a boss-specific rewrite'}\n"
        f"Gameplay context: {gameplay_context if gameplay_context else 'general combat preparation'}\n"
        f"Exact current task prompt: {prompt_focus}\n"
        f"Task keywords: {keyword_focus}\n"
        f"Validation targets: {target_focus}\n"
        f"Target code structure: {structure_target}\n"
        f"Gameplay focus for this attempt: {gameplay_focus}\n"
        f"Teaching angle for this attempt: {explanation_angle}\n"
        f"Theme nuance to stress: {subtopic_focus}\n"
        f"Hint tone: {hint_style['tone']}\n"
        f"Hint format: {hint_style['format']}\n"
        f"Hint avoidance rule: {hint_style['avoidance']}\n"
        f"Current code:\n{normalized_code}\n\n"
        f"Known validation errors:\n{error_block}\n\n"
        + altar_hint_block +
        boss_hint_block +
        f"Return up to {max_hints} short bullet hints in plain text. "
        "Make the hints fairly obvious, but stop before giving the final code. "
        "Keep them short for a fast in-game answer. "
        "Generate a fresh wording for this exact attempt instead of repeating one stock pattern. "
        "Stay strictly inside the current theme and current gameplay focus. "
        "Make the hint fit the current encounter and the intended code structure. "
        "If useful, mention one small nuance of the current theme, but do not drift into another lesson topic. "
        "Respect the real syntax and idioms of the specified language. "
        "Do not suggest constructs that belong to a different language. "
        "Do not include markdown fences. "
        "Do not provide a complete code answer."
    )


def _build_validation_prompt(
    *,
    interaction_type: InteractionType,
    level_theme: str,
    difficulty: Difficulty,
    language: str,
    encounter_name: str,
    encounter_style: str,
    gameplay_context: str,
    structure_focus: str,
    boss_mechanic: str,
    task_prompt: str,
    keywords: list[str],
    syntax_rules: list[str],
    code: str,
    strict_response_mode: bool = False,
) -> str:
    language_guidance: str = _language_guidance(language)
    strict_block: str = (
        "Use every tag exactly once. Keep PASS for code that clearly addresses the requested gameplay stats or actions by meaning. "
        "Return FAIL only when the code is too generic, incomplete, unreasonable, or unrelated to the requested concepts.\n"
        if strict_response_mode
        else ""
    )
    keyword_block: str = ", ".join(keywords) if keywords else "no explicit keywords provided"
    syntax_block: str = ", ".join(syntax_rules) if syntax_rules else "no explicit syntax rules provided"
    altar_validation_block: str = (
        "For altar tasks, judge whether the code meaningfully forges or tunes the requested weapon setup. "
        "Accept approximate variable names when they clearly match the requested weapon concepts, for example blade_power for melee damage, shot_power for ranged damage, parry_time for guard window, attack_reach for weapon range, or blade_balance for weapon weight. "
        "Reject code that is valid syntax but does not describe the requested forge stats or weapon behavior.\n"
        if interaction_type == "altar"
        else ""
    )
    return (
        "Evaluate whether the player's code matches the intent of the task.\n"
        "Return plain text using this exact tagged format:\n"
        "VERDICT: PASS or FAIL\n"
        "MATCH_SCORE: <0-100>\n"
        "REASON: <one short sentence>\n"
        "MISSING_KEYWORDS:\n- <missing or weakly matched concept>\n"
        "HINTS:\n- <short hint>\n- <short hint>\n"
        "Do not use JSON. Do not add commentary before VERDICT or after HINTS.\n"
        + strict_block +
        "Judge semantic fit, not exact spelling.\n"
        "The code should roughly map the task wording to meaningful variables, branches, loops, or functions.\n"
        "For beginner variable tasks, accept readable variable names that match the meaning even when they do not exactly match the task text.\n"
        "Examples: attack_power can match damage, move_speed can match speed, barrier_strength can match shield, and parry_time can match guard window.\n"
        "Approximate correspondence is allowed, but generic unrelated code should fail.\n"
        "If the task asks for damage, speed, guard window, shield, hp, or similar combat concepts, the code should clearly reflect those ideas with reasonable values.\n"
        + altar_validation_block +
        "Respect the target language syntax and naming conventions.\n"
        f"Programming language: {language}\n"
        f"Language rules: {language_guidance}\n"
        f"Interaction type: {interaction_type}\n"
        f"Theme: {level_theme}\n"
        f"Difficulty: {difficulty}\n"
        f"Encounter name: {encounter_name if encounter_name else 'unspecified encounter'}\n"
        f"Encounter style: {encounter_style if encounter_style else 'generic'}\n"
        f"Boss mechanic: {boss_mechanic if boss_mechanic else 'not a boss-specific rewrite'}\n"
        f"Gameplay context: {gameplay_context if gameplay_context else 'general combat preparation'}\n"
        f"Target structure: {structure_focus if structure_focus else 'compact beginner-friendly snippet'}\n"
        f"Task prompt: {task_prompt if task_prompt else 'no prompt provided'}\n"
        f"Expected keywords: {keyword_block}\n"
        f"Syntax rules: {syntax_block}\n"
        f"Submitted code:\n{code.strip() or '<empty>'}\n"
    )


def _build_task_prompt(
    *,
    interaction_type: InteractionType,
    level_theme: str,
    difficulty: Difficulty,
    language: str,
    encounter_name: str,
    encounter_style: str,
    gameplay_context: str,
    structure_focus: str,
    boss_mechanic: str,
    tutorial_mode: bool,
    adaptation_reason: str,
    strict_response_mode: bool = False,
) -> str:
    language_guidance: str = _language_guidance(language)
    theme_pack: dict[str, list[str]] = _theme_variation_pack(level_theme)
    writing_pack: dict[str, str] = RNG.choice(TASK_WRITING_PACKS)
    gameplay_focus: str = RNG.choice(theme_pack["gameplay_focuses"])
    explanation_angle: str = RNG.choice(theme_pack["explanation_angles"])
    subtopic_focus: str = RNG.choice(theme_pack["subtopics"])
    example_style: str = RNG.choice(theme_pack["example_styles"])
    structure_target: str = structure_focus.strip() if structure_focus.strip() else RNG.choice(theme_pack["structure_focuses"])
    variant_tag: str = _random_variant_tag()
    strict_block: str = (
        "Use every tag exactly once. Keep each tagged section present. "
        "Do not merge PROMPT and EXPLANATION_BODY. "
        "Do not omit KEYWORDS or EXAMPLE_CODE. "
        "Keep list sections as bullet lines that begin with '- '.\n"
        if strict_response_mode
        else ""
    )
    altar_task_block: str = (
        "This request is for a forge altar, not a normal enemy. "
        "The generated task, hints, explanation, keywords, validation_targets, and example must all describe the same forged weapon setup. "
        "Use altar language such as forge, blade, weapon, rune, hilt, shield sigil, reach, ranged rune, guard timing, or recovery seal. "
        "For variables altar tasks, ask for two or three obvious weapon-stat assignments and provide suggested readable name styles. "
        "For non-variable altar tasks, keep the required structure inside the current theme while still making the code affect weapon behavior. "
        "Do not mix unrelated enemy-combat tasks into altar tasks.\n"
        if interaction_type == "altar"
        else ""
    )
    return (
        "Return plain text using this exact tagged format and no extra commentary:\n"
        "TITLE: <one short line>\n"
        "PROMPT: <main task text>\n"
        "GAMEPLAY_EFFECT: <one short gameplay sentence>\n"
        "SYNTAX_RULES:\n- <rule one>\n- <rule two>\n"
        "EXPLANATION_TITLE: <theme title>\n"
        "EXPLANATION_PROMPT: <how to read the task without repeating it>\n"
        "EXPLANATION_BODY: <teaching text that explains the theme rather than restating the task>\n"
        "EXPLANATION_RULES:\n- <rule one>\n- <rule two>\n"
        "KEYWORDS:\n- <keyword one>\n- <keyword two>\n"
        "VALIDATION_TARGETS:\n- <descriptive concept or acceptable variable-name family>\n- <another descriptive concept>\n"
        "EXAMPLE_CODE:\n<short study example only>\n"
        "Do not use JSON. Do not use markdown headings. Do not add any text before TITLE or after EXAMPLE_CODE.\n"
        + strict_block +
        "The task must fit a beginner programming student inside an action platformer.\n"
        "Every variable, condition, loop, or function must directly affect gameplay like damage, hp, speed, shield, or timing.\n"
        "The task must stay strictly inside the current level theme.\n"
        "The explanation must also stay strictly inside the same theme and explain only that concept.\n"
        "The explanation_prompt must be different from the main task prompt. "
        "It should tell the player how to read the task text and search for key words, not restate the task itself.\n"
        "The keywords field must contain short key phrases from the task text that help the player map the wording to code.\n"
        "The validation_targets field must contain descriptive gameplay concepts and acceptable variable-name families such as "
        "'attack damage', 'damage', 'attack_power', or 'strike_power' when they all fit the same task.\n"
        "Those keywords should also appear naturally inside the task prompt and the explanation.\n"
        "For variable tasks, make the requested variable ideas obvious to a human reader from the wording of the prompt itself. "
        "Use clear gameplay phrases like attack damage, movement speed, shield durability, health pool, or guard window.\n"
        "For variable tasks, include a short suggested naming style inside the prompt, such as 'use names like attack_power or move_speed'. "
        "These names are hints, not the only accepted answers.\n"
        + altar_task_block +
        "The player should not need an exact variable-name match. Similar names that match the same meaning should still make sense.\n"
        "Do not drift into other topics from other levels.\n"
        "If the interaction type is boss, explain the same theme only in the context of this boss fight. "
        "Do not switch to unrelated mechanics from other bosses or levels.\n"
        "Provide one short example_code snippet for study only. "
        "The real player answer must still require their own work and the example must not be treated as the final accepted answer.\n"
        "The example should make the important keywords visually obvious by placing them in comments or nearby labels, but it must not be identical to the task answer.\n"
        "Generate a fresh task variant for this request rather than a stock repeated prompt.\n"
        "Keep the generated explanation, rules, and example tightly aligned with the exact same task variant.\n"
        f"Programming language: {language}\n"
        f"Language rules: {language_guidance}\n"
        f"Interaction type: {interaction_type}\n"
        f"Theme: {level_theme}\n"
        f"Difficulty: {difficulty}\n"
        f"Adaptation reason: {adaptation_reason}\n"
        f"Encounter name: {encounter_name if encounter_name else 'unspecified encounter'}\n"
        f"Encounter style: {encounter_style if encounter_style else 'generic'}\n"
        f"Boss mechanic: {boss_mechanic if boss_mechanic else 'not a boss-specific rewrite'}\n"
        f"Gameplay context: {gameplay_context if gameplay_context else 'general combat preparation'}\n"
        f"Variation tag: {variant_tag}\n"
        f"Task shape: {writing_pack['task_shape']}\n"
        f"Task voice: {writing_pack['task_voice']}\n"
        f"Explanation shape: {writing_pack['explanation_shape']}\n"
        f"Gameplay focus: {gameplay_focus}\n"
        f"Theme nuance to teach: {subtopic_focus}\n"
        f"Target code structure: {structure_target}\n"
        f"Explanation angle: {explanation_angle}\n"
        f"Example style: {example_style}\n"
        f"Tutorial mode: {'on' if tutorial_mode else 'off'}\n"
        f"Theme nuance guidance: {_theme_nuance_guidance(level_theme)}\n"
        "Make the task, explanation, and example feel tied to the current encounter rather than abstract homework. "
        "The explanation should explicitly mention one or two nuanced basics of the current theme. "
        "For example, variables may mention types, reassignment, or simple operators if relevant. "
        "However, keep the generated code itself beginner-friendly and short.\n"
        "Respect the syntax and beginner-friendly style of the specified language. "
        "Do not include markdown fences unless they are inside EXAMPLE_CODE, and raw code is preferred."
    )


def _call_responses_api(
    *,
    api_url: str,
    api_key: str,
    model: str,
    timeout_seconds: float,
    user_prompt: str,
    max_output_tokens: int = 64,
    temperature: float = 0.7,
) -> str:
    payload = {
        "model": model,
        "input": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_prompt},
        ],
        "text": {"verbosity": "low"},
        "max_output_tokens": max_output_tokens,
        "temperature": temperature,
    }
    request = Request(
        api_url,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urlopen(request, timeout=timeout_seconds) as response:
        body = json.loads(response.read().decode("utf-8"))
    return _extract_response_text(body)


def _call_chat_completions_api(
    *,
    api_url: str,
    api_key: str,
    model: str,
    timeout_seconds: float,
    user_prompt: str,
    max_output_tokens: int = 64,
    temperature: float = 0.7,
) -> str:
    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_prompt},
        ],
        "temperature": temperature,
        "max_tokens": max_output_tokens,
        "stream": False,
    }
    request = Request(
        api_url,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urlopen(request, timeout=timeout_seconds) as response:
        body = json.loads(response.read().decode("utf-8"))
    return _extract_chat_completion_text(body)


def _call_responses_api_with_model_fallback(
    *,
    api_url: str,
    api_key: str,
    models: list[str],
    timeout_seconds: float,
    user_prompt: str,
    max_output_tokens: int = 64,
    temperature: float = 0.7,
) -> tuple[str, str]:
    last_http_error: HTTPError | None = None
    last_other_error: Exception | None = None
    settings = get_settings()
    for model in models:
        try:
            return (
                _call_provider_text(
                    provider=settings.llm_provider,
                    api_url=api_url,
                    api_key=api_key,
                    model=model,
                    timeout_seconds=timeout_seconds,
                    user_prompt=user_prompt,
                    max_output_tokens=max_output_tokens,
                    temperature=temperature,
                ),
                model,
            )
        except HTTPError as exc:
            last_http_error = exc
            if exc.code not in {429, 404}:
                raise
        except (URLError, TimeoutError, OSError, ValueError) as exc:
            last_other_error = exc
    if last_http_error is not None:
        raise last_http_error
    if last_other_error is not None:
        raise last_other_error
    raise ValueError("No AI models configured")


def _extract_response_text(body: dict) -> str:
    output = body.get("output", [])
    parts: list[str] = []
    for item in output:
        content_items = item.get("content", [])
        for content in content_items:
            if content.get("type") == "output_text":
                text_value: str = str(content.get("text", "")).strip()
                if text_value:
                    parts.append(text_value)
    if parts:
        return "\n".join(parts).strip()
    fallback_text: str = str(body.get("output_text", "")).strip()
    if fallback_text:
        return fallback_text
    raise ValueError("OpenAI response did not contain output text")


def _extract_chat_completion_text(body: dict) -> str:
    choices = body.get("choices", [])
    if not isinstance(choices, list) or not choices:
        raise ValueError("Chat completion response did not contain choices")
    first_choice = choices[0]
    if not isinstance(first_choice, dict):
        raise ValueError("Chat completion choice was invalid")
    message = first_choice.get("message", {})
    if not isinstance(message, dict):
        raise ValueError("Chat completion message was invalid")
    content = message.get("content", "")
    if isinstance(content, str) and content.strip():
        return content.strip()
    if isinstance(content, list):
        parts: list[str] = []
        for item in content:
            if isinstance(item, dict):
                text_value = str(item.get("text", "")).strip()
                if text_value:
                    parts.append(text_value)
        if parts:
            return "\n".join(parts).strip()
    raise ValueError("Chat completion response did not contain text content")


def _call_provider_text(
    *,
    provider: str,
    api_url: str,
    api_key: str,
    model: str,
    timeout_seconds: float,
    user_prompt: str,
    max_output_tokens: int = 64,
    temperature: float = 0.7,
) -> str:
    normalized_provider: str = provider.strip().lower()
    if normalized_provider in {"qwen_compatible_chat", "openai_compatible_chat", "compatible_chat"}:
        return _call_chat_completions_api(
            api_url=api_url,
            api_key=api_key,
            model=model,
            timeout_seconds=timeout_seconds,
            user_prompt=user_prompt,
            max_output_tokens=max_output_tokens,
            temperature=temperature,
        )
    return _call_responses_api(
        api_url=api_url,
        api_key=api_key,
        model=model,
        timeout_seconds=timeout_seconds,
        user_prompt=user_prompt,
        max_output_tokens=max_output_tokens,
        temperature=temperature,
    )


def _parse_hint_lines(response_text: str, max_hints: int) -> list[str]:
    hints: list[str] = []
    for raw_line in response_text.splitlines():
        line: str = raw_line.strip().lstrip("-").lstrip("*").strip()
        if line:
            hints.append(line)
        if len(hints) >= max_hints:
            break
    if not hints and response_text.strip():
        hints.append(response_text.strip())
    return hints[:max_hints]


def _extract_json_object(response_text: str) -> dict:
    stripped_text: str = response_text.strip()
    candidates: list[str] = []
    if stripped_text:
        candidates.append(stripped_text)
    if stripped_text.startswith("```"):
        parts = stripped_text.split("```")
        fenced_candidate: str = next((part for part in parts if "{" in part and "}" in part), "").strip()
        if fenced_candidate.startswith("json"):
            fenced_candidate = fenced_candidate[4:].strip()
        if fenced_candidate:
            candidates.append(fenced_candidate)
    start_index: int = stripped_text.find("{")
    end_index: int = stripped_text.rfind("}")
    if start_index != -1 and end_index != -1 and end_index > start_index:
        candidates.append(stripped_text[start_index : end_index + 1])
    for candidate in candidates:
        try:
            parsed: object = json.loads(candidate)
            if isinstance(parsed, dict):
                return parsed
        except json.JSONDecodeError:
            repaired: str = _repair_json_candidate(candidate)
            try:
                parsed = json.loads(repaired)
                if isinstance(parsed, dict):
                    return parsed
            except json.JSONDecodeError:
                continue
    raise ValueError("JSON object not found in response")


def _extract_task_payload(response_text: str) -> dict:
    tagged_payload: dict = _extract_tagged_task_payload(response_text)
    if tagged_payload:
        return _cleanup_task_payload(tagged_payload)
    json_payload: dict = _extract_json_object(response_text)
    return _cleanup_task_payload(json_payload)


def _extract_validation_payload(response_text: str) -> dict:
    tags: tuple[str, ...] = ("VERDICT", "MATCH_SCORE", "REASON", "MISSING_KEYWORDS", "HINTS")
    buckets: dict[str, list[str]] = {tag: [] for tag in tags}
    current_tag: str | None = None
    for raw_line in response_text.splitlines():
        stripped_line: str = raw_line.strip()
        matched_tag: str | None = None
        for tag in tags:
            prefix: str = f"{tag}:"
            if stripped_line.upper().startswith(prefix):
                matched_tag = tag
                remainder: str = stripped_line[len(prefix) :].strip()
                current_tag = tag
                if remainder:
                    buckets[tag].append(remainder)
                break
        if matched_tag is not None:
            continue
        if current_tag is not None:
            buckets[current_tag].append(raw_line.rstrip())
    if not any(buckets["VERDICT"]):
        return {}
    verdict_text: str = _join_tagged_text(buckets["VERDICT"]).strip().upper()
    score_text: str = _join_tagged_text(buckets["MATCH_SCORE"]).strip()
    try:
        match_score: int = int(re.sub(r"[^0-9]", "", score_text) or "0")
    except ValueError:
        match_score = 0
    return {
        "verdict": verdict_text,
        "match_score": max(0, min(100, match_score)),
        "reason": _join_tagged_text(buckets["REASON"]),
        "missing_keywords": _parse_tagged_list(buckets["MISSING_KEYWORDS"]),
        "hints": _parse_tagged_list(buckets["HINTS"]),
    }


def _extract_tagged_task_payload(response_text: str) -> dict:
    tags: tuple[str, ...] = (
        "TITLE",
        "PROMPT",
        "GAMEPLAY_EFFECT",
        "SYNTAX_RULES",
        "EXPLANATION_TITLE",
        "EXPLANATION_PROMPT",
        "EXPLANATION_BODY",
        "EXPLANATION_RULES",
        "KEYWORDS",
        "VALIDATION_TARGETS",
        "EXAMPLE_CODE",
    )
    buckets: dict[str, list[str]] = {tag: [] for tag in tags}
    current_tag: str | None = None
    for raw_line in response_text.splitlines():
        stripped_line: str = raw_line.strip()
        matched_tag: str | None = None
        for tag in tags:
            prefix: str = f"{tag}:"
            if stripped_line.upper().startswith(prefix):
                matched_tag = tag
                remainder: str = stripped_line[len(prefix) :].strip()
                current_tag = tag
                if remainder:
                    buckets[tag].append(remainder)
                break
        if matched_tag is not None:
            continue
        if current_tag is not None:
            buckets[current_tag].append(raw_line.rstrip())
    if not any(buckets["TITLE"]) or not any(buckets["PROMPT"]):
        return {}
    return {
        "title": _join_tagged_text(buckets["TITLE"]),
        "prompt": _join_tagged_text(buckets["PROMPT"]),
        "gameplay_effect": _join_tagged_text(buckets["GAMEPLAY_EFFECT"]),
        "syntax_rules": _parse_tagged_list(buckets["SYNTAX_RULES"]),
        "explanation_title": _join_tagged_text(buckets["EXPLANATION_TITLE"]),
        "explanation_prompt": _join_tagged_text(buckets["EXPLANATION_PROMPT"]),
        "explanation_body": _join_tagged_text(buckets["EXPLANATION_BODY"]),
        "explanation_rules": _parse_tagged_list(buckets["EXPLANATION_RULES"]),
        "keywords": _parse_tagged_list(buckets["KEYWORDS"]),
        "validation_targets": _parse_tagged_list(buckets["VALIDATION_TARGETS"]),
        "example_code": _strip_code_fences(_join_tagged_code(buckets["EXAMPLE_CODE"])),
    }


def _repair_json_candidate(candidate: str) -> str:
    repaired: str = candidate.strip()
    repaired = repaired.replace("\u201c", '"').replace("\u201d", '"').replace("\u2018", "'").replace("\u2019", "'")
    repaired = re.sub(r",\s*([}\]])", r"\1", repaired)
    return repaired


def _normalize_string_list(value: object) -> list[str]:
    if not isinstance(value, list):
        return []
    items: list[str] = []
    for entry in value:
        text: str = str(entry).strip()
        if text:
            items.append(text)
    return items


def _cleanup_task_payload(task_payload: dict) -> dict:
    cleaned_payload: dict = dict(task_payload)
    text_keys: tuple[str, ...] = (
        "title",
        "prompt",
        "gameplay_effect",
        "explanation_title",
        "explanation_body",
        "explanation_prompt",
        "example_code",
    )
    for key in text_keys:
        cleaned_payload[key] = str(cleaned_payload.get(key, "")).strip()
    cleaned_payload["syntax_rules"] = _normalize_string_list(cleaned_payload.get("syntax_rules", []))
    cleaned_payload["explanation_rules"] = _normalize_string_list(cleaned_payload.get("explanation_rules", []))
    cleaned_payload["keywords"] = _normalize_string_list(cleaned_payload.get("keywords", []))
    cleaned_payload["validation_targets"] = _normalize_string_list(cleaned_payload.get("validation_targets", []))
    if not cleaned_payload["validation_targets"]:
        cleaned_payload["validation_targets"] = list(cleaned_payload["keywords"])
    cleaned_payload["example_code"] = _strip_code_fences(str(cleaned_payload.get("example_code", "")).strip())
    prompt_text: str = str(cleaned_payload.get("prompt", "")).strip()
    cleaned_payload["explanation_prompt"] = _strip_prompt_overlap(
        prompt_text,
        str(cleaned_payload.get("explanation_prompt", "")).strip(),
    )
    cleaned_payload["explanation_body"] = _strip_prompt_overlap(
        prompt_text,
        str(cleaned_payload.get("explanation_body", "")).strip(),
    )
    return cleaned_payload


def _is_valid_validation_payload(payload: dict) -> bool:
    verdict: str = str(payload.get("verdict", "")).strip().upper()
    if verdict not in {"PASS", "FAIL"}:
        return False
    if not str(payload.get("reason", "")).strip():
        return False
    hints: list[str] = _normalize_string_list(payload.get("hints", []))
    if not hints:
        return False
    return True


def _is_valid_task_payload(task_payload: dict) -> bool:
    required_text_keys: tuple[str, ...] = (
        "title",
        "prompt",
        "gameplay_effect",
        "explanation_title",
        "explanation_body",
        "explanation_prompt",
        "example_code",
    )
    for key in required_text_keys:
        if not str(task_payload.get(key, "")).strip():
            return False
    syntax_rules: list[str] = _normalize_string_list(task_payload.get("syntax_rules", []))
    explanation_rules: list[str] = _normalize_string_list(task_payload.get("explanation_rules", []))
    keywords: list[str] = _normalize_string_list(task_payload.get("keywords", []))
    validation_targets: list[str] = _normalize_string_list(task_payload.get("validation_targets", []))
    if not syntax_rules or not explanation_rules or not keywords or not validation_targets:
        return False
    prompt_text: str = str(task_payload.get("prompt", "")).strip().lower()
    explanation_prompt: str = str(task_payload.get("explanation_prompt", "")).strip().lower()
    if prompt_text == explanation_prompt:
        return False
    if _normalized_text(prompt_text) == _normalized_text(str(task_payload.get("explanation_body", ""))):
        return False
    return True


def _join_tagged_text(lines: list[str]) -> str:
    filtered_lines: list[str] = [line.strip() for line in lines if line.strip()]
    return " ".join(filtered_lines).strip()


def _join_tagged_code(lines: list[str]) -> str:
    return "\n".join(line.rstrip() for line in lines).strip()


def _parse_tagged_list(lines: list[str]) -> list[str]:
    items: list[str] = []
    for raw_line in lines:
        stripped_line: str = raw_line.strip()
        if not stripped_line:
            continue
        stripped_line = re.sub(r"^[-*•]\s*", "", stripped_line)
        if stripped_line:
            items.append(stripped_line)
    if len(items) == 1 and "," in items[0]:
        comma_items: list[str] = [part.strip() for part in items[0].split(",") if part.strip()]
        if len(comma_items) > 1:
            return comma_items
    return items


def _strip_code_fences(code_text: str) -> str:
    stripped_code: str = code_text.strip()
    if stripped_code.startswith("```") and stripped_code.endswith("```"):
        stripped_code = re.sub(r"^```[a-zA-Z0-9_+-]*\s*", "", stripped_code)
        stripped_code = re.sub(r"\s*```$", "", stripped_code)
    return stripped_code.strip()


def _strip_prompt_overlap(prompt_text: str, candidate_text: str) -> str:
    stripped_candidate: str = candidate_text.strip()
    if not stripped_candidate:
        return stripped_candidate
    prompt_lines: list[str] = [line.strip() for line in prompt_text.splitlines() if line.strip()]
    candidate_lines: list[str] = [line.strip() for line in stripped_candidate.splitlines() if line.strip()]
    if prompt_lines and candidate_lines:
        prompt_line_set: set[str] = {_normalized_text(line) for line in prompt_lines}
        filtered_lines: list[str] = [line for line in candidate_lines if _normalized_text(line) not in prompt_line_set]
        if filtered_lines:
            stripped_candidate = "\n".join(filtered_lines).strip()
    normalized_prompt: str = _normalized_text(prompt_text)
    normalized_candidate: str = _normalized_text(stripped_candidate)
    if normalized_prompt and normalized_prompt == normalized_candidate:
        return ""
    return stripped_candidate


def _normalized_text(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip().lower()


def _language_guidance(language: str) -> str:
    normalized_language: str = language.strip().lower()
    if normalized_language in {"python", "py"}:
        return (
            "Use Python syntax with indentation, def for functions, if/elif/else, "
            "for/while loops, and quoted strings. Avoid braces and semicolons."
        )
    if normalized_language in {"gdscript", "godot"}:
        return (
            "Use GDScript syntax with indentation, func for functions, if/elif/else, "
            "for/while loops, typed variables when helpful, and no braces."
        )
    if normalized_language in {"javascript", "js"}:
        return (
            "Use JavaScript syntax with braces, function or const arrow functions, "
            "if/else, for/while loops, and semicolons only if consistent."
        )
    return (
        "Respect the requested language syntax and beginner-friendly conventions. "
        "Do not mix syntax from different languages."
    )


def _response_attempt_models() -> list[str]:
    settings = get_settings()
    models: list[str] = [settings.llm_model]
    for model in settings.llm_fallback_models:
        if model not in models:
            models.append(model)
    return models


def _theme_variation_pack(level_theme: str) -> dict[str, list[str]]:
    return THEME_VARIATION_PACKS.get(level_theme, THEME_VARIATION_PACKS["integration"])


def _random_variant_tag() -> str:
    left: str = RNG.choice(["ember", "pulse", "vault", "cinder", "echo", "signal", "glint", "arc"])
    right: str = RNG.choice(["alpha", "beta", "gamma", "delta", "theta", "lambda", "sigma", "omega"])
    return f"{left}-{right}-{RNG.randint(100, 999)}"


def _theme_nuance_guidance(level_theme: str) -> str:
    if level_theme == "variables":
        return (
            "You may highlight variable types like int, float, string, or bool, simple reassignment, "
            "or simple operators like += and -=, but keep the task beginner-friendly."
        )
    if level_theme == "conditions":
        return (
            "You may highlight comparison operators, boolean checks, and/or, and readable branching, "
            "but stay focused on one combat decision."
        )
    if level_theme == "loops":
        return (
            "You may highlight for with range, while with a stop rule, counters, and avoiding endless repetition, "
            "but keep the loop small and clear."
        )
    if level_theme == "functions":
        return (
            "You may highlight parameters, return values, local variables, and reuse, "
            "but keep the function short and readable."
        )
    return (
        "You may highlight how several simple constructs work together, but keep the explanation focused and readable."
    )


def _build_hint_cache_key(
    *,
    interaction_type: InteractionType,
    level_theme: str,
    difficulty: Difficulty,
    language: str,
    encounter_name: str,
    encounter_style: str,
    gameplay_context: str,
    structure_focus: str,
    boss_mechanic: str,
    task_prompt: str,
    keywords: list[str],
    validation_targets: list[str],
    code: str,
    errors: list[str],
    max_hints: int,
) -> str:
    return json.dumps(
        {
            "kind": "hint",
            "interaction_type": interaction_type,
            "level_theme": level_theme,
            "difficulty": difficulty,
            "language": language,
            "encounter_name": encounter_name,
            "encounter_style": encounter_style,
            "gameplay_context": gameplay_context,
            "structure_focus": structure_focus,
            "boss_mechanic": boss_mechanic,
            "task_prompt": task_prompt,
            "keywords": keywords,
            "validation_targets": validation_targets,
            "code": code.strip(),
            "errors": errors,
            "max_hints": max_hints,
        },
        ensure_ascii=False,
        sort_keys=True,
    )


def _get_cached_hints(cache_key: str, ttl_seconds: float) -> list[str] | None:
    if ttl_seconds <= 0.0:
        return None
    cached_entry = _HINT_CACHE.get(cache_key)
    if cached_entry is None:
        return None
    expires_at, cached_hints = cached_entry
    if expires_at <= time.monotonic():
        _HINT_CACHE.pop(cache_key, None)
        return None
    return list(cached_hints)


def _store_cached_hints(cache_key: str, hints: list[str]) -> None:
    settings = get_settings()
    if settings.llm_hint_cache_ttl_seconds <= 0.0 or not hints:
        return
    _HINT_CACHE[cache_key] = (time.monotonic() + settings.llm_hint_cache_ttl_seconds, list(hints))


def _activate_rate_limit_cooldown(exc: HTTPError, default_cooldown_seconds: float) -> None:
    global _RATE_LIMIT_UNTIL_MONOTONIC
    global _RATE_LIMIT_REASON
    global _RATE_LIMIT_IS_TEMPORARY

    retry_after_header = None
    if getattr(exc, "headers", None) is not None:
        retry_after_header = exc.headers.get("Retry-After")
    error_detail: str = _extract_http_error_detail(exc)
    if _is_quota_error_detail(error_detail):
        _RATE_LIMIT_UNTIL_MONOTONIC = time.monotonic() + max(300.0, default_cooldown_seconds)
        _RATE_LIMIT_REASON = "AI quota exceeded or billing unavailable"
        _RATE_LIMIT_IS_TEMPORARY = False
        return
    cooldown_seconds: float = _parse_retry_after_seconds(retry_after_header, default_cooldown_seconds)
    _RATE_LIMIT_UNTIL_MONOTONIC = time.monotonic() + cooldown_seconds
    _RATE_LIMIT_REASON = "AI cooldown after rate limit"
    _RATE_LIMIT_IS_TEMPORARY = True


def _get_rate_limit_detail() -> str | None:
    remaining_seconds: float = _RATE_LIMIT_UNTIL_MONOTONIC - time.monotonic()
    if remaining_seconds <= 0.0:
        return None
    if _RATE_LIMIT_IS_TEMPORARY:
        return "%s (%ss remaining)" % (_RATE_LIMIT_REASON, int(max(1, round(remaining_seconds))))
    return _RATE_LIMIT_REASON


def _parse_retry_after_seconds(retry_after_value: str | None, default_seconds: float) -> float:
    if not retry_after_value:
        return max(1.0, default_seconds)
    try:
        return max(1.0, float(retry_after_value.strip()))
    except ValueError:
        return max(1.0, default_seconds)


def _extract_http_error_detail(exc: HTTPError) -> str:
    try:
        payload_bytes = exc.read()
    except Exception:
        return ""
    if not payload_bytes:
        return ""
    try:
        payload = json.loads(payload_bytes.decode("utf-8", errors="ignore"))
    except ValueError:
        return payload_bytes.decode("utf-8", errors="ignore").strip()
    error_payload = payload.get("error", {})
    if isinstance(error_payload, dict):
        message = str(error_payload.get("message", "")).strip()
        error_type = str(error_payload.get("type", "")).strip()
        error_code = str(error_payload.get("code", "")).strip()
        return " | ".join([part for part in [message, error_type, error_code] if part])
    return str(payload).strip()


def _is_quota_error_detail(error_detail: str) -> bool:
    normalized: str = error_detail.strip().lower()
    if not normalized:
        return False
    return (
        "insufficient_quota" in normalized
        or "quota" in normalized
        or "billing" in normalized
        or "exceeded your current quota" in normalized
    )


def _summarize_provider_error(error_detail: str) -> str:
    normalized: str = error_detail.strip()
    if not normalized:
        return "access denied by AI provider"
    lowered: str = normalized.lower()
    if "provider" in lowered and "available" in lowered:
        return "no available provider for this model"
    if "does not support" in lowered or "unsupported" in lowered:
        return "requested model or parameter is unsupported"
    if "bad request" in lowered or "invalid" in lowered:
        return "request format rejected by AI provider"
    if "authorization" in lowered or "unauthorized" in lowered or "invalid token" in lowered:
        return "token rejected by AI provider"
    if "permission" in lowered or "forbidden" in lowered or "not allowed" in lowered:
        return "model or endpoint access denied"
    if "gated" in lowered or "access" in lowered:
        return "model access denied for this token"
    if len(normalized) > 140:
        return normalized[:140] + "..."
    return normalized
