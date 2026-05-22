from __future__ import annotations

import os
from functools import lru_cache
from pathlib import Path

from pydantic import BaseModel, Field


ENV_FILE_PATH = Path(__file__).resolve().parents[1] / ".env"


class AppSettings(BaseModel):
    llm_enabled: bool = Field(default=False)
    llm_provider: str = Field(default="qwen_compatible_chat")
    llm_model: str = Field(default="Qwen/Qwen2.5-Coder-32B-Instruct")
    llm_fallback_models: list[str] = Field(default_factory=lambda: ["Qwen/Qwen2.5-Coder-32B-Instruct", "Qwen/Qwen2.5-Coder-7B-Instruct", "Qwen/Qwen2.5-7B-Instruct"])
    llm_api_url: str = Field(default="https://router.huggingface.co/v1/chat/completions")
    llm_api_key: str = Field(default="")
    llm_timeout_seconds: float = Field(default=10.0)
    llm_max_hints: int = Field(default=2)
    llm_task_cache_ttl_seconds: float = Field(default=180.0)
    llm_hint_cache_ttl_seconds: float = Field(default=45.0)
    llm_rate_limit_cooldown_seconds: float = Field(default=30.0)


def _env_flag(name: str, default: bool = False) -> bool:
    raw_value: str = os.getenv(name, str(default)).strip().lower()
    return raw_value in {"1", "true", "yes", "on"}


def _env_flag_any(names: tuple[str, ...], default: bool = False) -> bool:
    for name in names:
        raw_value: str | None = os.getenv(name)
        if raw_value is not None and raw_value.strip():
            return raw_value.strip().lower() in {"1", "true", "yes", "on"}
    return default


def _env_first(*names: str) -> str:
    for name in names:
        raw_value: str = os.getenv(name, "").strip()
        if raw_value:
            return raw_value
    return ""


def _load_dotenv() -> None:
    if not ENV_FILE_PATH.exists():
        return
    for raw_line in ENV_FILE_PATH.read_text(encoding="utf-8").splitlines():
        line: str = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        env_key: str = key.strip()
        env_value: str = value.strip().strip('"').strip("'")
        if env_key and env_key not in os.environ:
            os.environ[env_key] = env_value


@lru_cache(maxsize=1)
def get_settings() -> AppSettings:
    _load_dotenv()
    preferred_model: str = (
        _env_first("SKILL_ISSUE_LLM_MODEL", "CODEKNIGHT_LLM_MODEL")
        or os.getenv("HF_MODEL", "").strip()
        or os.getenv("OPENROUTER_MODEL", "").strip()
        or os.getenv("QWEN_MODEL", "").strip()
        or os.getenv("OPENAI_MODEL", "").strip()
        or "Qwen/Qwen3-Coder-480B-A35B-Instruct"
    )
    preferred_api_url: str = (
        _env_first("SKILL_ISSUE_LLM_API_URL", "CODEKNIGHT_LLM_API_URL")
        or os.getenv("HF_API_URL", "").strip()
        or os.getenv("OPENROUTER_API_URL", "").strip()
        or os.getenv("QWEN_API_URL", "").strip()
        or "https://router.huggingface.co/v1/chat/completions"
    )
    provider_raw: str = _env_first("SKILL_ISSUE_LLM_PROVIDER", "CODEKNIGHT_LLM_PROVIDER").lower()
    if not provider_raw:
        provider_raw = "qwen_compatible_chat" if "chat/completions" in preferred_api_url else "openai_responses"
    elif provider_raw == "openai_responses" and "chat/completions" in preferred_api_url:
        provider_raw = "qwen_compatible_chat"
    fallback_models_raw: str = _env_first("SKILL_ISSUE_LLM_FALLBACK_MODELS", "CODEKNIGHT_LLM_FALLBACK_MODELS") or "Qwen/Qwen2.5-Coder-32B-Instruct,Qwen/Qwen2.5-Coder-7B-Instruct,Qwen/Qwen2.5-7B-Instruct"
    fallback_models: list[str] = [item.strip() for item in fallback_models_raw.split(",") if item.strip()]
    return AppSettings(
        llm_enabled=_env_flag_any(("SKILL_ISSUE_LLM_ENABLED", "CODEKNIGHT_LLM_ENABLED"), True),
        llm_provider=provider_raw,
        llm_model=preferred_model,
        llm_fallback_models=fallback_models,
        llm_api_url=preferred_api_url,
        llm_api_key="",
        llm_timeout_seconds=float(_env_first("SKILL_ISSUE_LLM_TIMEOUT_SECONDS", "CODEKNIGHT_LLM_TIMEOUT_SECONDS") or "10"),
        llm_max_hints=max(1, int(_env_first("SKILL_ISSUE_LLM_MAX_HINTS", "CODEKNIGHT_LLM_MAX_HINTS") or "2")),
        llm_task_cache_ttl_seconds=max(0.0, float(_env_first("SKILL_ISSUE_LLM_TASK_CACHE_TTL_SECONDS", "CODEKNIGHT_LLM_TASK_CACHE_TTL_SECONDS") or "180")),
        llm_hint_cache_ttl_seconds=max(0.0, float(_env_first("SKILL_ISSUE_LLM_HINT_CACHE_TTL_SECONDS", "CODEKNIGHT_LLM_HINT_CACHE_TTL_SECONDS") or "45")),
        llm_rate_limit_cooldown_seconds=max(1.0, float(_env_first("SKILL_ISSUE_LLM_RATE_LIMIT_COOLDOWN_SECONDS", "CODEKNIGHT_LLM_RATE_LIMIT_COOLDOWN_SECONDS") or "30")),
    )
