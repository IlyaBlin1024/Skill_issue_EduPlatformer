from __future__ import annotations

import ast
from typing import Literal

from fastapi import FastAPI
from pydantic import BaseModel, Field


app = FastAPI(title="CodeKnight AI Service", version="0.1.0")


class CombatValidationRequest(BaseModel):
    user_id: str = Field(default="anon_local")
    level_theme: Literal["variables", "conditions", "loops", "functions", "integration"]
    difficulty: Literal["easy", "normal", "hard"] = "easy"
    code: str
    time_taken_seconds: int = 0


class CombatValidationResponse(BaseModel):
    success: bool
    damage: int
    errors: list[str]
    hints: list[str]
    suggested_difficulty: Literal["easy", "normal", "hard"]


THEME_HINTS = {
    "variables": "Use assignment to store a value before you try to use it.",
    "conditions": "Try an if/else branch that checks a single clear condition.",
    "loops": "A loop should repeat a small action with a clear stopping rule.",
    "functions": "Wrap repeated logic in a function and call it with clear inputs.",
    "integration": "Combine variables, branches, loops, or functions into one small tactic.",
}


def _difficulty_damage(difficulty: str) -> int:
    return {"easy": 40, "normal": 30, "hard": 20}[difficulty]


def _next_difficulty(success: bool, difficulty: str, time_taken_seconds: int) -> str:
    order = ["easy", "normal", "hard"]
    index = order.index(difficulty)
    if success and time_taken_seconds < 45 and index < len(order) - 1:
        return order[index + 1]
    if not success and index > 0:
        return order[index - 1]
    return difficulty


def _theme_checks(theme: str, tree: ast.AST) -> list[str]:
    issues: list[str] = []
    if theme == "variables":
        has_assignment = any(isinstance(node, ast.Assign) for node in ast.walk(tree))
        if not has_assignment:
            issues.append("expected at least one assignment")
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


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/validate/combat", response_model=CombatValidationResponse)
def validate_combat(payload: CombatValidationRequest) -> CombatValidationResponse:
    errors: list[str] = []
    hints: list[str] = []

    try:
        tree = ast.parse(payload.code)
        errors.extend(_theme_checks(payload.level_theme, tree))
    except SyntaxError as exc:
        line = exc.lineno or 1
        errors.append(f"syntax error on line {line}: {exc.msg}")

    if errors:
        hints.append(THEME_HINTS[payload.level_theme])
        if payload.difficulty != "hard":
            hints.append("Start with the smallest valid snippet that matches the level theme.")

    success = not errors
    damage = _difficulty_damage(payload.difficulty) if success else 0
    suggested_difficulty = _next_difficulty(success, payload.difficulty, payload.time_taken_seconds)

    return CombatValidationResponse(
        success=success,
        damage=damage,
        errors=errors,
        hints=hints,
        suggested_difficulty=suggested_difficulty,
    )
