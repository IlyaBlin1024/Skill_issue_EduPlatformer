Skill Issue release package

How to run:
1. Double-click SkillIssue.bat.
2. The launcher starts the local FastAPI backend on http://127.0.0.1:8000.
3. The launcher starts SkillIssue.exe.
4. When the game closes, the launcher stops the backend it started.

First run notes:
- If Python 3.11+ is missing, the launcher tries to install Python 3.12 automatically through winget.
- On first run, the launcher creates .runtime/backend-venv and installs backend requirements.
- If another backend is already running on port 8000, the launcher uses it instead.
- For AI generation, paste a Hugging Face token in the game Settings screen.
- backend/.env is optional and only used for backend model/URL overrides. The release package includes only backend/.env.example.
- Settings can export player logs to an Excel workbook in Downloads.

Files:
- SkillIssue.exe: exported Godot game.
- SkillIssue.bat: recommended launcher.
- run_skill_issue.ps1: backend + game launcher.
- backend/: local API service used by the game.
