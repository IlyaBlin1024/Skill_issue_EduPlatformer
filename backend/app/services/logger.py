from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4

from app.models import ValidationRequest, ValidationResponse


LOG_DIRECTORY = Path(__file__).resolve().parents[2] / "data"
LOG_FILE_PATH = LOG_DIRECTORY / "validation_attempts.jsonl"


def log_validation_attempt(payload: ValidationRequest, result: ValidationResponse) -> str:
    LOG_DIRECTORY.mkdir(parents=True, exist_ok=True)
    attempt_id: str = str(uuid4())
    record = {
        "attempt_id": attempt_id,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "user_id": payload.user_id,
        "interaction_type": payload.interaction_type,
        "level_theme": payload.level_theme,
        "difficulty": payload.difficulty,
        "suggested_difficulty": result.suggested_difficulty,
        "time_taken_seconds": payload.time_taken_seconds,
        "success": result.success,
        "damage": result.damage,
        "errors": result.errors,
        "hints": result.hints,
        "code_submitted": payload.code,
        "normalized_code": result.normalized_code,
    }
    with LOG_FILE_PATH.open("a", encoding="utf-8") as log_file:
        log_file.write(json.dumps(record, ensure_ascii=True) + "\n")
    return attempt_id


def read_recent_attempts(limit: int = 20) -> list[dict]:
    if not LOG_FILE_PATH.exists():
        return []
    lines: list[str] = LOG_FILE_PATH.read_text(encoding="utf-8").splitlines()
    recent_lines: list[str] = lines[-max(limit, 1):]
    attempts: list[dict] = []
    for line in recent_lines:
        try:
            attempts.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return attempts
