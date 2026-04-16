from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field


LevelTheme = Literal["variables", "conditions", "loops", "functions", "integration"]
Difficulty = Literal["easy", "normal", "hard"]
InteractionType = Literal["combat", "chest", "altar", "boss"]


class ValidationRequest(BaseModel):
    user_id: str = Field(default="anon_local")
    interaction_type: InteractionType = "combat"
    level_theme: LevelTheme
    difficulty: Difficulty = "easy"
    code: str
    time_taken_seconds: int = 0


class HintRequest(BaseModel):
    user_id: str = Field(default="anon_local")
    interaction_type: InteractionType = "combat"
    level_theme: LevelTheme
    difficulty: Difficulty = "easy"
    code: str = ""


class ValidationResponse(BaseModel):
    success: bool
    damage: int = 0
    errors: list[str]
    hints: list[str]
    suggested_difficulty: Difficulty
    interaction_type: InteractionType
    normalized_code: str = ""
    attempt_id: str = ""


class HintResponse(BaseModel):
    interaction_type: InteractionType
    hints: list[str]
