from fastapi import FastAPI

from app.models import HintRequest, HintResponse, ValidationRequest, ValidationResponse
from app.services.logger import log_validation_attempt, read_recent_attempts
from app.services.validator import generate_hints, validate_submission

app = FastAPI(title="CodeKnight AI Service", version="0.1.0")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/logs/recent")
def logs_recent(limit: int = 20) -> dict[str, list[dict]]:
    return {"items": read_recent_attempts(limit)}


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
