from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field


LevelTheme = Literal["variables", "conditions", "loops", "functions", "integration"]
Difficulty = Literal["easy", "normal", "hard"]
InteractionType = Literal["combat", "chest", "altar", "boss"]


class ValidationRequest(BaseModel):
    user_id: str = Field(default="anon_local")
    interaction_type: InteractionType = "combat"
    stage_type: str = ""
    level_id: str = ""
    level_theme: LevelTheme
    difficulty: Difficulty = "easy"
    language: str = Field(default="python")
    encounter_name: str = ""
    encounter_style: str = ""
    gameplay_context: str = ""
    structure_focus: str = ""
    boss_mechanic: str = ""
    task_prompt: str = ""
    keywords: list[str] = []
    syntax_rules: list[str] = []
    fallback_hints: list[str] = []
    validation_targets: list[str] = []
    generation_source: str = ""
    generation_detail: str = ""
    pattern_id: str = ""
    terminal_session_id: str = ""
    attempt_number: int = 0
    task_generation_seconds: float = 0.0
    hint_used: bool = False
    explanation_used: bool = False
    hint_request_count: int = 0
    explanation_open_count: int = 0
    explanation_read_seconds: float = 0.0
    code: str
    example_code: str = ""
    time_taken_seconds: int = 0
    generation_mode: str = "ai"
    llm_api_key: str = ""


class HintRequest(BaseModel):
    user_id: str = Field(default="anon_local")
    interaction_type: InteractionType = "combat"
    level_theme: LevelTheme
    difficulty: Difficulty = "easy"
    language: str = Field(default="python")
    encounter_name: str = ""
    encounter_style: str = ""
    gameplay_context: str = ""
    structure_focus: str = ""
    boss_mechanic: str = ""
    task_prompt: str = ""
    keywords: list[str] = []
    validation_targets: list[str] = []
    fallback_hints: list[str] = []
    code: str = ""
    generation_mode: str = "ai"
    llm_api_key: str = ""


class ValidationResponse(BaseModel):
    success: bool
    damage: int = 0
    errors: list[str]
    hints: list[str]
    resolved_effects: dict = {}
    suggested_difficulty: Difficulty
    interaction_type: InteractionType
    normalized_code: str = ""
    attempt_id: str = ""


class HintResponse(BaseModel):
    interaction_type: InteractionType
    hints: list[str]


class TaskGenerationRequest(BaseModel):
    user_id: str = Field(default="anon_local")
    interaction_type: InteractionType = "combat"
    level_theme: LevelTheme
    language: str = Field(default="python")
    encounter_name: str = ""
    encounter_style: str = ""
    gameplay_context: str = ""
    structure_focus: str = ""
    boss_mechanic: str = ""
    tutorial_mode: bool = False
    generation_mode: str = "ai"
    llm_api_key: str = ""


class TaskGenerationResponse(BaseModel):
    interaction_type: InteractionType
    level_theme: LevelTheme
    difficulty: Difficulty
    language: str = "python"
    generation_source: str = "fallback"
    generation_detail: str = ""
    title: str
    prompt: str
    gameplay_effect: str
    syntax_rules: list[str]
    explanation_title: str = ""
    explanation_body: str = ""
    explanation_rules: list[str] = []
    explanation_prompt: str = ""
    keywords: list[str] = []
    example_code: str = ""
    adaptation_reason: str = ""
    fallback_hints: list[str] = []
    validation_targets: list[str] = []
    pattern_id: str = ""


class AnalyticsEventRequest(BaseModel):
    user_id: str = Field(default="anon_local")
    session_id: str = ""
    save_slot: int = 0
    event_type: str
    stage_type: str = ""
    level_id: str = ""
    progress_percent: int = 0
    timestamp_unix: int = 0
    metadata: dict = Field(default_factory=dict)
