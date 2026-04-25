@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_skill_issue.ps1"
if errorlevel 1 pause
