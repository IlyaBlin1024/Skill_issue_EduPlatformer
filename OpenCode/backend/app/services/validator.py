from __future__ import annotations

import ast
import random
import re

from app.models import Difficulty, HintRequest, HintResponse, InteractionType, ValidationRequest, ValidationResponse
from app.services.llm import evaluate_llm_submission_with_detail, generate_llm_hints


FALLBACK_THEME_HINTS = {
    "variables": [
        "Use assignment to store a value before you try to use it.",
        "Start by naming one stat and giving it one number.",
        "Write one gameplay variable per line before combining anything else.",
    ],
    "conditions": [
        "Try an if/else branch that checks a single clear condition.",
        "Decide which one combat state should lead to which one action.",
        "Write one branch for the risky case and one for the safer alternative.",
    ],
    "loops": [
        "A loop should repeat a small action with a clear stopping rule.",
        "Repeat one useful combat step instead of writing many separate lines.",
        "Keep the loop body small and make the repeat count obvious.",
    ],
    "functions": [
        "Wrap repeated logic in a function and call it with clear inputs.",
        "Give the tactic a short function name and call it after defining it.",
        "Move the repeated action into def first, then use the function.",
    ],
    "integration": [
        "Combine variables, branches, loops, or functions into one small tactic.",
        "Pick two compatible ideas and connect them into one readable snippet.",
        "Use only the constructs that directly help the current gameplay effect.",
    ],
}

FALLBACK_INTERACTION_HINTS = {
    "combat": [
        "Keep the snippet short and focused on the current attack pattern.",
        "Solve the immediate combat need first and ignore extra flourishes.",
    ],
    "chest": [
        "Assign the required values directly before adding anything extra.",
        "Chest tasks are usually cleaner when you solve the core requirement first.",
    ],
    "altar": [
        "Declare weapon variables first, then adjust their values.",
        "For altar tasks, define the weapon setup before you tune it.",
    ],
    "boss": [
        "Build the tactic in small valid steps before combining them.",
        "Boss tasks are easier when you start with one safe valid piece of code.",
    ],
}

RNG = random.SystemRandom()

CONCEPT_SYNONYMS: dict[str, list[str]] = {
    "weapon": ["weapon", "blade", "sword", "forge", "forged weapon", "hilt", "core", "rune", "sigil"],
    "weapon_mode": ["weapon mode", "attack mode", "combat mode", "blade mode", "form"],
    "weapon_range": ["weapon range", "attack range", "strike reach", "reach", "range"],
    "weapon_weight": ["weapon weight", "blade weight", "weapon balance", "balance", "weight"],
    "damage": ["damage", "attack damage", "attack_power", "attack power", "strike power", "hit power", "power"],
    "melee_damage": ["melee damage", "blade damage", "slash damage", "sword damage", "strike damage"],
    "ranged_damage": ["ranged damage", "projectile damage", "shot damage", "volley damage", "bolt damage"],
    "speed": ["speed", "movement speed", "move speed", "mobility", "dash speed", "rush speed", "agility"],
    "guard_window": ["guard window", "parry window", "block timing", "deflect timing", "guard timing"],
    "recovery": ["recovery", "recovery timing", "cooldown", "reset timing", "recharge timing"],
    "hp": ["hp", "health", "integrity", "vitality", "health pool", "health_value"],
    "shield": ["shield", "barrier", "shield durability", "barrier strength", "protection"],
    "armor": ["armor", "defense", "durability", "protection layer"],
    "stamina": ["stamina", "energy", "combat energy", "energy reserve", "focus reserve"],
    "projectile_speed": ["projectile speed", "shot speed", "bolt speed", "volley speed"],
    "attack_delay": ["attack delay", "attack timing", "attack cooldown", "strike delay"],
    "jump_height": ["jump height", "air height", "jump reach"],
    "crit_damage": ["critical damage", "crit damage", "critical power", "critical hit power"],
    "crit_window": ["critical window", "crit window", "critical timing"],
}

SUCCESS_DAMAGE = {"easy": 40, "normal": 30, "hard": 20}
DIFFICULTY_ORDER: list[Difficulty] = ["easy", "normal", "hard"]


def validate_submission(payload: ValidationRequest) -> ValidationResponse:
    normalized_code: str = payload.code.strip()
    errors: list[str] = _preflight_checks(payload.interaction_type, normalized_code, payload.example_code)
    hints: list[str] = []
    tree: ast.AST | None = None
    resolved_effects: dict = {}

    if not errors:
        try:
            tree = ast.parse(normalized_code)
            errors.extend(_theme_checks(payload.level_theme, payload.interaction_type, tree))
        except SyntaxError as exc:
            line = exc.lineno or 1
            errors.append(f"syntax error on line {line}: {exc.msg}")

    if not errors:
        semantic_issues, semantic_hints = _semantic_validation(payload, normalized_code)
        errors.extend(semantic_issues)
        hints.extend(semantic_hints)

    if not errors and tree is not None:
        resolved_effects = _derive_runtime_effects(payload, tree, normalized_code)

    if errors:
        if not hints:
            hints.extend(
                _resolve_hints(
                    interaction_type=payload.interaction_type,
                    level_theme=payload.level_theme,
                    difficulty=payload.difficulty,
                    language=payload.language,
                    encounter_name=payload.encounter_name,
                    encounter_style=payload.encounter_style,
                gameplay_context=payload.gameplay_context,
                structure_focus=payload.structure_focus,
                boss_mechanic=payload.boss_mechanic,
                task_prompt=payload.task_prompt,
                keywords=payload.keywords,
                validation_targets=payload.validation_targets,
                fallback_hints=payload.fallback_hints,
                code=normalized_code,
                errors=errors,
            )
            )

    success: bool = not errors
    damage: int = SUCCESS_DAMAGE[payload.difficulty] if success and payload.interaction_type in ("combat", "boss") else 0
    suggested_difficulty: Difficulty = _next_difficulty(
        success=success,
        difficulty=payload.difficulty,
        time_taken_seconds=payload.time_taken_seconds,
        interaction_type=payload.interaction_type,
    )

    return ValidationResponse(
        success=success,
        damage=damage,
        errors=errors,
        hints=hints,
        resolved_effects=resolved_effects,
        suggested_difficulty=suggested_difficulty,
        interaction_type=payload.interaction_type,
        normalized_code=normalized_code,
    )


def generate_hints(payload: HintRequest) -> HintResponse:
    normalized_code: str = payload.code.strip()
    preflight_errors: list[str] = _preflight_checks(payload.interaction_type, normalized_code, "")
    theme_errors: list[str] = []
    if normalized_code and not preflight_errors:
        try:
            tree = ast.parse(normalized_code)
            theme_errors = _theme_checks(payload.level_theme, payload.interaction_type, tree)
        except SyntaxError as exc:
            line = exc.lineno or 1
            theme_errors = [f"syntax error on line {line}: {exc.msg}"]
    hints: list[str] = _resolve_hints(
        interaction_type=payload.interaction_type,
        level_theme=payload.level_theme,
        difficulty=payload.difficulty,
        language=payload.language,
        encounter_name=payload.encounter_name,
        encounter_style=payload.encounter_style,
        gameplay_context=payload.gameplay_context,
        structure_focus=payload.structure_focus,
        boss_mechanic=payload.boss_mechanic,
        task_prompt=payload.task_prompt,
        keywords=payload.keywords,
        validation_targets=payload.validation_targets,
        fallback_hints=payload.fallback_hints,
        code=normalized_code,
        errors=preflight_errors + theme_errors,
    )
    return HintResponse(interaction_type=payload.interaction_type, hints=hints)


def build_fallback_hints(interaction_type: InteractionType, level_theme: str, code: str, errors: list[str]) -> list[str]:
    hints: list[str] = [
        RNG.choice(FALLBACK_THEME_HINTS[level_theme]),
        RNG.choice(FALLBACK_INTERACTION_HINTS[interaction_type]),
    ]
    if not code:
        hints.append(_starter_hint_for_theme(level_theme, interaction_type))
        return hints
    if errors:
        hints.append(_error_hint(errors[0]))
    else:
        hints.append("Your structure is valid so far. Adjust variable names or values carefully.")
    return hints


def _preflight_checks(interaction_type: InteractionType, code: str, example_code: str) -> list[str]:
    issues: list[str] = []
    if not code:
        issues.append("code is empty")
        return issues
    if _matches_example_solution(code, example_code):
        issues.append("example code cannot be submitted as the final answer")
        return issues
    non_empty_lines: list[str] = [line.strip() for line in code.splitlines() if line.strip()]
    if interaction_type in ("chest", "altar") and len(non_empty_lines) < 2:
        issues.append("expected at least two meaningful lines")
    return issues


def _matches_example_solution(code: str, example_code: str) -> bool:
    if not example_code.strip():
        return False
    return _normalize_for_example_compare(code) == _normalize_for_example_compare(example_code)


def _normalize_for_example_compare(value: str) -> str:
    normalized_parts: list[str] = []
    for raw_line in value.splitlines():
        line: str = raw_line.strip().replace(" ", "").replace("\t", "")
        if line:
            normalized_parts.append(line)
    return "\n".join(normalized_parts)


def _next_difficulty(success: bool, difficulty: Difficulty, time_taken_seconds: int, interaction_type: InteractionType) -> Difficulty:
    index: int = DIFFICULTY_ORDER.index(difficulty)
    promotion_threshold: int = 45 if interaction_type in ("combat", "boss") else 30
    if success and time_taken_seconds < promotion_threshold and index < len(DIFFICULTY_ORDER) - 1:
        return DIFFICULTY_ORDER[index + 1]
    if not success and index > 0 and interaction_type in ("combat", "boss"):
        return DIFFICULTY_ORDER[index - 1]
    return difficulty


def _theme_checks(theme: str, interaction_type: InteractionType, tree: ast.AST) -> list[str]:
    issues: list[str] = []
    if theme == "variables":
        issues.extend(_variables_checks(interaction_type, tree))
    elif theme == "conditions":
        has_if = any(isinstance(node, ast.If) for node in ast.walk(tree))
        if not has_if:
            issues.append("expected an if statement")
    elif theme == "loops":
        has_loop = any(isinstance(node, (ast.For, ast.While)) for node in ast.walk(tree))
        if not has_loop:
            issues.append("expected a for or while loop")
    elif theme == "functions":
        has_function = any(isinstance(node, ast.FunctionDef) for node in ast.walk(tree))
        if not has_function:
            issues.append("expected a function definition")
    elif theme == "integration":
        kinds = {
            "assign": any(isinstance(node, ast.Assign) for node in ast.walk(tree)),
            "if": any(isinstance(node, ast.If) for node in ast.walk(tree)),
            "loop": any(isinstance(node, (ast.For, ast.While)) for node in ast.walk(tree)),
            "function": any(isinstance(node, ast.FunctionDef) for node in ast.walk(tree)),
        }
        if sum(kinds.values()) < 2:
            issues.append("expected at least two core programming constructs")
    return issues


def _variables_checks(interaction_type: InteractionType, tree: ast.AST) -> list[str]:
    assignments: list[ast.AST] = [
        node
        for node in ast.walk(tree)
        if isinstance(node, (ast.Assign, ast.AnnAssign, ast.AugAssign))
    ]
    if not assignments:
        return ["expected at least one assignment"]

    assignment_targets: list[str] = []
    for assignment in assignments:
        if isinstance(assignment, ast.Assign):
            for target in assignment.targets:
                if isinstance(target, ast.Name):
                    assignment_targets.append(target.id)
        elif isinstance(assignment, ast.AnnAssign) and isinstance(assignment.target, ast.Name):
            assignment_targets.append(assignment.target.id)
        elif isinstance(assignment, ast.AugAssign) and isinstance(assignment.target, ast.Name):
            assignment_targets.append(assignment.target.id)

    if interaction_type in ("chest", "altar") and len(assignment_targets) < 2:
        return ["expected at least two variable assignments"]

    if interaction_type == "altar":
        weapon_related_targets: list[str] = [
            target
            for target in assignment_targets
            if _classify_name_concepts(target.lower()).intersection(_altar_concepts())
        ]
        if len(weapon_related_targets) < 2:
            return ["expected at least two meaningful weapon or combat stat assignments"]

    return []


def _starter_hint_for_theme(level_theme: str, interaction_type: InteractionType) -> str:
    if level_theme == "variables" and interaction_type == "altar":
        return "Start with weapon_type = 'melee' and weapon_damage = 15."
    if level_theme == "variables":
        return "Start by assigning one gameplay stat per line, like damage and speed."
    if level_theme == "conditions":
        return "Start with one if/else branch that picks between two actions."
    if level_theme == "loops":
        return "Start with a short loop that repeats one simple combat action."
    if level_theme == "functions":
        return "Declare one small helper function, then call it once."
    return "Combine two simple constructs before expanding the tactic."


def _error_hint(first_error: str) -> str:
    if "syntax error" in first_error:
        return "Check punctuation, quotes, and indentation first."
    if "assignment" in first_error:
        return "Add explicit variable assignments before using the values."
    if "if statement" in first_error:
        return "Write one clear if condition, then fill in the body."
    if "loop" in first_error:
        return "Use a single for or while loop with one simple action inside."
    if "function definition" in first_error:
        return "Define the function with def name(...): before calling it."
    return "Reduce the snippet to the smallest version that still matches the task."


def _merge_ai_hints(existing_hints: list[str], ai_hints: list[str]) -> list[str]:
    seen: set[str] = {hint.strip().lower() for hint in existing_hints}
    merged: list[str] = []
    for hint in ai_hints:
        normalized_hint: str = hint.strip()
        if not normalized_hint:
            continue
        key: str = normalized_hint.lower()
        if key in seen:
            continue
        seen.add(key)
        merged.append(normalized_hint)
    return merged


def _semantic_validation(payload: ValidationRequest, code: str) -> tuple[list[str], list[str]]:
    local_issues: list[str] = _keyword_heuristic_issues(payload, code)
    value_issues: list[str] = _reasonable_assignment_issues(code)
    if value_issues:
        return value_issues, [
            "Keep stat values in a believable gameplay range.",
            "Use positive, modest numbers for combat stats unless the task clearly asks for something else.",
        ]
    if payload.level_theme == "variables" and not local_issues:
        return [], []

    ai_result, ai_detail = evaluate_llm_submission_with_detail(
        interaction_type=payload.interaction_type,
        level_theme=payload.level_theme,
        difficulty=payload.difficulty,
        language=payload.language,
        encounter_name=payload.encounter_name,
        encounter_style=payload.encounter_style,
        gameplay_context=payload.gameplay_context,
        structure_focus=payload.structure_focus,
        boss_mechanic=payload.boss_mechanic,
        task_prompt=payload.task_prompt,
        keywords=_combined_semantic_terms(payload),
        syntax_rules=payload.syntax_rules,
        code=code,
    )
    if ai_result is not None:
        verdict: str = str(ai_result.get("verdict", "")).strip().upper()
        if verdict == "PASS":
            return [], []
        if not local_issues and payload.level_theme == "variables":
            return [], []
        reason: str = str(ai_result.get("reason", "")).strip() or "solution does not match the generated task closely enough"
        missing_keywords: list[str] = _normalize_keywords(ai_result.get("missing_keywords", []))
        hints: list[str] = _normalize_keywords(ai_result.get("hints", []))
        issues: list[str] = [reason]
        if missing_keywords:
            issues.append("missing or weak concepts: %s" % ", ".join(missing_keywords[:4]))
        return issues, hints

    if local_issues:
        heuristic_hints: list[str] = [
            "Use variable names or code structure that clearly match the requested combat concepts.",
            "Read the task text again and map the main stat or action words into your code more directly.",
        ]
        if ai_detail:
            heuristic_hints.append("AI semantic check fell back to local matching: %s." % ai_detail)
        return local_issues, heuristic_hints
    return [], []


def _keyword_heuristic_issues(payload: ValidationRequest, code: str) -> list[str]:
    validation_targets: list[str] = _normalize_keywords(payload.validation_targets)
    keywords: list[str] = _normalize_keywords(payload.keywords)
    terms_to_match: list[str] = validation_targets if validation_targets else keywords
    if not terms_to_match:
        return []
    code_identifiers: list[str] = _extract_identifier_terms(code)
    matched_terms: list[str] = []
    for keyword in terms_to_match:
        if _code_matches_semantic_term(code_identifiers, keyword):
            matched_terms.append(keyword)
    required_matches: int = max(1, min(_semantic_term_goal(terms_to_match), 3))
    if len(matched_terms) >= required_matches:
        return []
    missing_keywords: list[str] = [keyword for keyword in terms_to_match if keyword not in matched_terms]
    return ["solution is too generic and does not match enough task concepts: %s" % ", ".join(missing_keywords[:4])]


def _normalize_keywords(value: object) -> list[str]:
    if not isinstance(value, list):
        return []
    items: list[str] = []
    for entry in value:
        text: str = str(entry).strip()
        if text:
            items.append(text)
    return items


def _combined_semantic_terms(payload: ValidationRequest) -> list[str]:
    terms: list[str] = []
    for source in [payload.validation_targets, payload.keywords]:
        for term in _normalize_keywords(source):
            if term not in terms:
                terms.append(term)
    return terms


def _reasonable_assignment_issues(code: str) -> list[str]:
    try:
        tree = ast.parse(code)
    except SyntaxError:
        return []
    assignments: dict[str, object] = _extract_assignment_values(tree)
    issues: list[str] = []
    for variable_name, value in assignments.items():
        numeric_value: float | None = _to_float(value)
        if numeric_value is None:
            continue
        concept_set: set[str] = _classify_name_concepts(variable_name.lower())
        if not concept_set:
            continue
        if numeric_value < 0:
            issues.append("%s should not be negative for this beginner stat task" % variable_name)
            continue
        if {"hp", "shield", "armor", "stamina"}.intersection(concept_set):
            if numeric_value > 500:
                issues.append("%s is unrealistically high for this task" % variable_name)
        elif {"guard_window", "recovery", "attack_delay", "crit_window"}.intersection(concept_set):
            if numeric_value > 30:
                issues.append("%s is too large for a timing/window value" % variable_name)
        elif numeric_value > 250:
            issues.append("%s is too large for this combat stat" % variable_name)
    return issues[:3]


def _normalize_text_for_match(text: str) -> str:
    return re.sub(r"[^a-zA-Z0-9_]+", " ", text).strip().lower()


def _derive_runtime_effects(payload: ValidationRequest, tree: ast.AST, code: str) -> dict:
    assignments: dict[str, object] = _extract_assignment_values(tree)
    normalized_code: str = _normalize_text_for_match(code)
    focus_terms: list[str] = _normalize_keywords(payload.validation_targets)
    if not focus_terms:
        focus_terms = _normalize_keywords(payload.keywords)
    focus_concepts: set[str] = _resolve_focus_concepts(payload, focus_terms)

    player_effects: dict[str, float | int] = {}
    target_effects: dict[str, float | int] = {}

    for variable_name, value in assignments.items():
        name_key: str = variable_name.lower()
        numeric_value: float | None = _to_float(value)
        if numeric_value is None:
            continue
        var_name_concepts: set[str] = _classify_name_concepts(name_key)
        if not _matches_focus_terms(name_key, focus_terms, var_name_concepts):
            continue
        _accumulate_assignment_effects(player_effects, target_effects, payload, name_key, numeric_value, var_name_concepts, focus_concepts)

    _accumulate_theme_structure_effects(player_effects, target_effects, payload, normalized_code)

    player_effects = _strip_empty_effects(player_effects)
    target_effects = _strip_empty_effects(target_effects)
    summary: list[str] = _build_effect_summary(player_effects, target_effects, payload.interaction_type)

    return {
        "player": player_effects,
        "target": target_effects,
        "summary": summary,
    }


def _extract_assignment_values(tree: ast.AST) -> dict[str, object]:
    values: dict[str, object] = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign):
            extracted_value: object | None = _extract_literal_value(node.value)
            if extracted_value is None:
                continue
            for target in node.targets:
                if isinstance(target, ast.Name):
                    values[target.id] = extracted_value
        elif isinstance(node, ast.AnnAssign):
            extracted_value = _extract_literal_value(node.value)
            if extracted_value is None:
                continue
            if isinstance(node.target, ast.Name):
                values[node.target.id] = extracted_value
        elif isinstance(node, ast.AugAssign):
            extracted_value = _extract_literal_value(node.value)
            if extracted_value is None:
                continue
            if isinstance(node.target, ast.Name):
                values[node.target.id] = extracted_value
    return values


def _extract_literal_value(node: ast.AST | None) -> object | None:
    if node is None:
        return None
    if isinstance(node, ast.Constant):
        return node.value
    if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.USub) and isinstance(node.operand, ast.Constant):
        if isinstance(node.operand.value, (int, float)):
            return -float(node.operand.value)
    return None


def _to_float(value: object) -> float | None:
    if isinstance(value, bool):
        return 1.0 if value else 0.0
    if isinstance(value, (int, float)):
        return float(value)
    return None


def _matches_focus_terms(name_key: str, focus_terms: list[str], name_concepts: set[str] | None = None) -> bool:
    if not focus_terms:
        return True
    if name_concepts:
        for focus_term in focus_terms:
            if name_concepts.intersection(_semantic_variants(focus_term)):
                return True
    for focus_term in focus_terms:
        normalized_focus: str = focus_term.lower().replace(" ", "_")
        if normalized_focus in name_key or name_key in normalized_focus:
            return True
        focus_tokens: list[str] = [token for token in re.split(r"[^a-zA-Z0-9_]+", normalized_focus) if len(token) >= 3]
        if any(token in name_key for token in focus_tokens):
            return True
    return False


def _accumulate_assignment_effects(
    player_effects: dict[str, float | int],
    target_effects: dict[str, float | int],
    payload: ValidationRequest,
    name_key: str,
    numeric_value: float,
    name_concepts: set[str],
    focus_concepts: set[str],
) -> None:
    effective_concepts: set[str] = set(name_concepts)
    if not effective_concepts:
        effective_concepts = _classify_name_concepts(name_key)
    if focus_concepts:
        effective_concepts = effective_concepts.union(focus_concepts.intersection(effective_concepts))

    if {"damage", "melee_damage", "ranged_damage", "crit_damage"}.intersection(effective_concepts):
        if "ranged_damage" in effective_concepts or "projectile_speed" in effective_concepts or payload.encounter_style == "ranged":
            _add_effect(player_effects, "ranged_damage_bonus", int(round(clamp(numeric_value * 0.45, 2.0, 18.0))))
        else:
            _add_effect(player_effects, "melee_damage_bonus", int(round(clamp(numeric_value * 0.45, 2.0, 18.0))))
        _add_effect(target_effects, "health_delta", -int(round(clamp(numeric_value * 0.35, 1.0, 20.0))))
    if "speed" in effective_concepts:
        _add_effect(player_effects, "move_speed_bonus", int(round(clamp(numeric_value * 7.0, 10.0, 90.0))))
        _multiply_effect(target_effects, "move_speed_scale", 1.0 - clamp(numeric_value * 0.02, 0.05, 0.28))
    if {"guard_window", "recovery"}.intersection(effective_concepts):
        _add_effect(player_effects, "parry_window_bonus", round(clamp(numeric_value * 0.015, 0.02, 0.16), 3))
        _multiply_effect(target_effects, "attack_interval_scale", 1.0 + clamp(numeric_value * 0.03, 0.06, 0.35))
    if {"hp", "shield", "armor", "stamina"}.intersection(effective_concepts):
        _add_effect(player_effects, "heal_amount", int(round(clamp(numeric_value * 4.0, 6.0, 60.0))))
        _add_effect(player_effects, "failure_damage_reduction", int(round(clamp(numeric_value * 0.4, 2.0, 16.0))))
    if "projectile_speed" in effective_concepts:
        _add_effect(player_effects, "ranged_damage_bonus", int(round(clamp(numeric_value * 0.3, 2.0, 14.0))))
        _multiply_effect(target_effects, "projectile_speed_scale", 1.0 - clamp(numeric_value * 0.015, 0.05, 0.24))
    if "attack_delay" in effective_concepts:
        _add_effect(player_effects, "failure_damage_reduction", 2)
        _multiply_effect(target_effects, "attack_interval_scale", 1.0 + clamp(numeric_value * 0.025, 0.05, 0.24))
    if "weapon_range" in effective_concepts:
        _add_effect(player_effects, "ranged_damage_bonus", int(round(clamp(numeric_value * 0.25, 1.0, 10.0))))
        _multiply_effect(target_effects, "move_speed_scale", 1.0 - clamp(numeric_value * 0.01, 0.03, 0.15))
    if "weapon_weight" in effective_concepts:
        _add_effect(player_effects, "melee_damage_bonus", int(round(clamp(numeric_value * 0.3, 1.0, 12.0))))
        _add_effect(player_effects, "failure_damage_reduction", int(round(clamp(numeric_value * 0.2, 1.0, 6.0))))
    if payload.interaction_type == "boss":
        if any(marker in name_key for marker in ["boss", "phase", "pattern"]):
            _multiply_effect(target_effects, "attack_interval_scale", 1.08)
            _multiply_effect(target_effects, "move_speed_scale", 0.92)
    elif payload.interaction_type == "combat":
        if any(marker in name_key for marker in ["enemy", "sentinel", "range_limit"]):
            _multiply_effect(target_effects, "projectile_speed_scale", 0.9)
            _multiply_effect(target_effects, "attack_interval_scale", 1.08)


def _accumulate_theme_structure_effects(
    player_effects: dict[str, float | int],
    target_effects: dict[str, float | int],
    payload: ValidationRequest,
    normalized_code: str,
) -> None:
    if payload.level_theme == "conditions" and "if " in normalized_code:
        _add_effect(player_effects, "failure_damage_reduction", 3)
        _multiply_effect(target_effects, "attack_interval_scale", 1.06)
    elif payload.level_theme == "loops" and ("for " in normalized_code or "while " in normalized_code):
        _add_effect(player_effects, "ranged_damage_bonus", 4)
        _add_effect(player_effects, "melee_damage_bonus", 4)
        _multiply_effect(target_effects, "move_speed_scale", 0.95)
    elif payload.level_theme == "functions" and "def " in normalized_code:
        _add_effect(player_effects, "parry_window_bonus", 0.03)
        _add_effect(player_effects, "failure_damage_reduction", 4)
    elif payload.level_theme == "integration":
        _add_effect(player_effects, "melee_damage_bonus", 4)
        _add_effect(player_effects, "ranged_damage_bonus", 4)
        _add_effect(player_effects, "parry_window_bonus", 0.02)
        _multiply_effect(target_effects, "attack_interval_scale", 1.05)


def _add_effect(container: dict[str, float | int], key: str, amount: float | int) -> None:
    container[key] = container.get(key, 0) + amount


def _multiply_effect(container: dict[str, float | int], key: str, multiplier: float) -> None:
    current_value: float = float(container.get(key, 1.0))
    container[key] = round(current_value * multiplier, 3)


def _strip_empty_effects(container: dict[str, float | int]) -> dict[str, float | int]:
    cleaned: dict[str, float | int] = {}
    for key, value in container.items():
        if isinstance(value, float):
            if abs(value) < 0.0001:
                continue
            cleaned[key] = round(value, 3)
        elif isinstance(value, int):
            if value == 0:
                continue
            cleaned[key] = value
    return cleaned


def _build_effect_summary(player_effects: dict[str, float | int], target_effects: dict[str, float | int], interaction_type: InteractionType) -> list[str]:
    summary: list[str] = []
    if "melee_damage_bonus" in player_effects:
        summary.append("melee power increased")
    if "ranged_damage_bonus" in player_effects:
        summary.append("ranged power increased")
    if "move_speed_bonus" in player_effects:
        summary.append("movement speed increased")
    if "parry_window_bonus" in player_effects:
        summary.append("parry window widened")
    if "heal_amount" in player_effects:
        summary.append("integrity restored")
    if "failure_damage_reduction" in player_effects:
        summary.append("failure damage reduced")
    if interaction_type == "boss":
        if target_effects:
            summary.append("boss pattern weakened")
    elif interaction_type == "combat":
        if target_effects:
            summary.append("enemy archetype weakened")
    return summary


def _extract_identifier_terms(code: str) -> list[str]:
    identifiers: list[str] = []
    try:
        tree = ast.parse(code)
    except SyntaxError:
        tree = None
    if tree is not None:
        for node in ast.walk(tree):
            if isinstance(node, ast.Name):
                identifiers.append(node.id.lower())
            elif isinstance(node, ast.FunctionDef):
                identifiers.append(node.name.lower())
                identifiers.append("def")
                identifiers.append("function")
            elif isinstance(node, ast.If):
                identifiers.append("if")
                identifiers.append("condition")
            elif isinstance(node, (ast.For, ast.While)):
                identifiers.append("loop")
                identifiers.append("repeat")
            elif isinstance(node, ast.Call):
                identifiers.append("call")
            elif isinstance(node, (ast.Assign, ast.AnnAssign, ast.AugAssign)):
                identifiers.append("assignment")
    if identifiers:
        return identifiers
    return [token for token in re.findall(r"[A-Za-z_][A-Za-z0-9_]*", code.lower()) if len(token) >= 2]


def _semantic_term_goal(terms_to_match: list[str]) -> int:
    meaningful_terms: list[str] = [term for term in terms_to_match if len(term.strip()) >= 3]
    if not meaningful_terms:
        return 1
    if len(meaningful_terms) <= 2:
        return len(meaningful_terms)
    return 2


def _code_matches_semantic_term(code_identifiers: list[str], term: str) -> bool:
    expected_variants: set[str] = _semantic_variants(term)
    for identifier in code_identifiers:
        identifier_concepts: set[str] = _classify_name_concepts(identifier)
        if expected_variants.intersection(identifier_concepts):
            return True
        normalized_identifier: str = identifier.replace("_", " ")
        for variant in expected_variants:
            if variant in identifier or variant.replace("_", " ") in normalized_identifier:
                return True
    return False


def _resolve_focus_concepts(payload: ValidationRequest, focus_terms: list[str]) -> set[str]:
    concepts: set[str] = set()
    for source_text in focus_terms + [payload.task_prompt, payload.gameplay_context, payload.encounter_name, payload.boss_mechanic]:
        for concept in _classify_name_concepts(str(source_text).lower()):
            concepts.add(concept)
    return concepts


def _classify_name_concepts(name_text: str) -> set[str]:
    normalized_text: str = _normalize_text_for_match(name_text).replace(" ", "_")
    concepts: set[str] = set()
    for concept, aliases in CONCEPT_SYNONYMS.items():
        if concept in normalized_text:
            concepts.add(concept)
            continue
        for alias in aliases:
            normalized_alias: str = _normalize_text_for_match(alias).replace(" ", "_")
            if normalized_alias and (normalized_alias in normalized_text or normalized_text in normalized_alias):
                concepts.add(concept)
                break
            alias_tokens: list[str] = [token for token in normalized_alias.split("_") if len(token) >= 3]
            if alias_tokens and all(token in normalized_text for token in alias_tokens[: min(len(alias_tokens), 2)]):
                concepts.add(concept)
                break
    return concepts


def _altar_concepts() -> set[str]:
    return {
        "weapon",
        "weapon_mode",
        "weapon_range",
        "weapon_weight",
        "damage",
        "melee_damage",
        "ranged_damage",
        "speed",
        "guard_window",
        "recovery",
        "hp",
        "shield",
        "armor",
        "stamina",
        "projectile_speed",
        "attack_delay",
        "crit_damage",
        "crit_window",
    }


def _semantic_variants(term: str) -> set[str]:
    normalized_term: str = _normalize_text_for_match(term).replace(" ", "_")
    variants: set[str] = {normalized_term} if normalized_term else set()
    for concept, aliases in CONCEPT_SYNONYMS.items():
        if normalized_term == concept:
            variants.add(concept)
            variants.update(_normalize_text_for_match(alias).replace(" ", "_") for alias in aliases)
            continue
        for alias in aliases:
            normalized_alias: str = _normalize_text_for_match(alias).replace(" ", "_")
            if normalized_alias and (normalized_alias == normalized_term or normalized_alias in normalized_term or normalized_term in normalized_alias):
                variants.add(concept)
                variants.update(_normalize_text_for_match(item).replace(" ", "_") for item in aliases)
                break
    return {variant for variant in variants if variant}


def clamp(value: float, minimum: float, maximum: float) -> float:
    return max(minimum, min(value, maximum))


def _should_request_ai_hints(code: str) -> bool:
    return True


def _resolve_hints(
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
    fallback_hints: list[str],
    code: str,
    errors: list[str],
) -> list[str]:
    normalized_fallback_hints: list[str] = _normalize_keywords(fallback_hints)
    if interaction_type == "altar" and normalized_fallback_hints:
        return normalized_fallback_hints

    ai_hints: list[str] = []
    if _should_request_ai_hints(code):
        ai_hints = generate_llm_hints(
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
        )
    if ai_hints:
        return ai_hints
    if normalized_fallback_hints:
        return normalized_fallback_hints
    return build_fallback_hints(interaction_type, level_theme, code, errors)
