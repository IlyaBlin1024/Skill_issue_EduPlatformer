from fastapi import FastAPI
from fastapi.responses import FileResponse

from app.models import (
    AnalyticsEventRequest,
    HintRequest,
    HintResponse,
    TaskGenerationRequest,
    TaskGenerationResponse,
    ValidationRequest,
    ValidationResponse,
)
from app.services.logger import (
    export_player_logs_workbook,
    log_player_event,
    log_validation_attempt,
    read_recent_attempts,
)
from app.services.tasks import generate_task
from app.services.validator import generate_hints, validate_submission

app = FastAPI(title="Skill Issue AI Service", version="0.1.0")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/logs/recent")
def logs_recent(limit: int = 20) -> dict[str, list[dict]]:
    return {"items": read_recent_attempts(limit)}


@app.post("/logs/event")
def logs_event(payload: AnalyticsEventRequest) -> dict[str, str]:
    return {"event_id": log_player_event(payload)}


@app.get("/logs/export")
def logs_export() -> FileResponse:
    export_path = export_player_logs_workbook()
    return FileResponse(
        path=export_path,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        filename="Skill-Issue-player-logs.xlsx",
    )


@app.post("/validate", response_model=ValidationResponse)
def validate(payload: ValidationRequest) -> ValidationResponse:
    result = validate_submission(payload)
    result.attempt_id = log_validation_attempt(payload, result)
    return result


@app.post("/validate/combat", response_model=ValidationResponse)
def validate_combat(payload: ValidationRequest) -> ValidationResponse:
    request_payload = payload.model_copy(update={"interaction_type": "combat"})
    result = validate_submission(request_payload)
    result.attempt_id = log_validation_attempt(request_payload, result)
    return result


@app.post("/hints", response_model=HintResponse)
def hints(payload: HintRequest) -> HintResponse:
    return generate_hints(payload)


@app.post("/tasks/generate", response_model=TaskGenerationResponse)
def tasks_generate(payload: TaskGenerationRequest) -> TaskGenerationResponse:
    return generate_task(payload)
