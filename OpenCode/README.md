# Skill Issue

Skill Issue is an educational 2D action-platformer prototype built with Godot 4 and a Python AI service.

This repository currently contains a Sprint 1 scaffold:

- Godot project structure
- player movement controller
- enemy encounter pause flow
- Combat Terminal UI
- FastAPI validation service for code submissions

## Repository Layout

- `docs/design.md` - project design document
- `godot/` - Godot 4 client project
- `backend/` - Python FastAPI service

## Sprint 1 Goals

1. Core movement and traversal baseline
2. Pause-on-encounter combat flow
3. Combat Terminal with timer and Run action
4. Basic Godot to Python request/response loop

## Run Backend

1. Optional: create a local environment file for backend model/URL overrides:

```powershell
cd backend
copy .env.example .env
```

2. Keep `backend/.env` local only. It is ignored by Git.
   Hugging Face API keys are entered in the game Settings screen, not in open-source files.

3. Start the backend:

```powershell
cd backend
.\run_backend.bat
```

The default API URL expected by the Godot client is `http://127.0.0.1:8000`.

## Open Godot Project

Open the project located in `godot/project.godot` with Godot 4.x.
