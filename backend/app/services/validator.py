from __future__ import annotations

import ast

from app.models import Difficulty, HintRequest, HintResponse, InteractionType, ValidationRequest, ValidationResponse


THEME_HINTS = {
    "variables": "Use assignment to store a value before you try to use it.",
    "conditions": "Try an if/else branch that checks a single clear condition.",
    "loops": "A loop should repeat a small action with a clear stopping rule.",
    "functions": "Wrap repeated logic in a function and call it with clear inputs.",
    "integration": "Combine variables, branches, loops, or functions into one small tactic.",
}

INTERACTION_HINTS = {
    "combat": "Keep the snippet short and focused on the current attack pattern.",
    "chest": "Assign the required values directly before adding anything extra.",
    "altar": "Declare weapon variables first, then adjust their values.",
    "boss": "Build the tactic in small valid steps before combining them.",
}

SUCCESS_DAMAGE = {"easy": 40, "normal": 30, "hard": 20}
DIFFICULTY_ORDER: list[Difficulty] = ["easy", "normal", "hard"]


def validate_submission(payload: ValidationRequest) -> ValidationResponse:
    normalized_code: str = payload.code.strip()
    errors: list[str] = _preflight_checks(payload.interaction_type, normalized_code)
    hints: list[str] = []

    if not errors:
        try:
            tree = ast.parse(normalized_code)
            errors.extend(_theme_checks(payload.level_theme, payload.interaction_type, tree))
        except SyntaxError as exc:
            line = exc.lineno or 1
            errors.append(f"syntax error on line {line}: {exc.msg}")

    if errors:
        hints.extend(build_hints(payload.interaction_type, payload.level_theme, normalized_code, errors))
        if payload.difficulty != "hard":
            hints.append("Start with the smallest valid snippet that matches the task.")

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
        suggested_difficulty=suggested_difficulty,
        interaction_type=payload.interaction_type,
        normalized_code=normalized_code,
    )


def generate_hints(payload: HintRequest) -> HintResponse:
    normalized_code: str = payload.code.strip()
    preflight_errors: list[str] = _preflight_checks(payload.interaction_type, normalized_code)
    theme_errors: list[str] = []
    if normalized_code and not preflight_errors:
        try:
            tree = ast.parse(normalized_code)
            theme_errors = _theme_checks(payload.level_theme, payload.interaction_type, tree)
        except SyntaxError as exc:
            line = exc.lineno or 1
            theme_errors = [f"syntax error on line {line}: {exc.msg}"]
    hints: list[str] = build_hints(payload.interaction_type, payload.level_theme, normalized_code, preflight_errors + theme_errors)
    return HintResponse(interaction_type=payload.interaction_type, hints=hints)


def build_hints(interaction_type: InteractionType, level_theme: str, code: str, errors: list[str]) -> list[str]:
    hints: list[str] = [THEME_HINTS[level_theme], INTERACTION_HINTS[interaction_type]]
    if not code:
        hints.append(_starter_hint_for_theme(level_theme, interaction_type))
        return hints
    if errors:
        hints.append(_error_hint(errors[0]))
    else:
        hints.append("Your structure is valid so far. Adjust variable names or values carefully.")
    return hints


def _preflight_checks(interaction_type: InteractionType, code: str) -> list[str]:
    issues: list[str] = []
    if not code:
        issues.append("code is empty")
        return issues
    non_empty_lines: list[str] = [line.strip() for line in code.splitlines() if line.strip()]
    if interaction_type in ("chest", "altar") and len(non_empty_lines) < 2:
        issues.append("expected at least two meaningful lines")
    return issues


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
    assignments: list[ast.Assign] = [node for node in ast.walk(tree) if isinstance(node, ast.Assign)]
    if not assignments:
        return ["expected at least one assignment"]

    assignment_targets: list[str] = []
    for assignment in assignments:
        for target in assignment.targets:
            if isinstance(target, ast.Name):
                assignment_targets.append(target.id)

    if interaction_type in ("chest", "altar") and len(assignment_targets) < 2:
        return ["expected at least two variable assignments"]

    if interaction_type == "altar":
        required_names = {"weapon_type", "weapon_damage"}
        if not required_names.issubset(set(assignment_targets)):
            return ["expected weapon_type and weapon_damage assignments"]

    return []


def _starter_hint_for_theme(level_theme: str, interaction_type: InteractionType) -> str:
    if level_theme == "variables" and interaction_type == "altar":
        return "Start with weapon_type = 'melee' and weapon_damage = 15."
    if level_theme == "variables":
        return "Try two simple assignments like damage = 12 and speed = 4."
    if level_theme == "conditions":
        return "Start with one if statement before adding extra branches."
    if level_theme == "loops":
        return "Start with a short for loop that repeats one action."
    if level_theme == "functions":
        return "Declare one small function, then call it once."
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
