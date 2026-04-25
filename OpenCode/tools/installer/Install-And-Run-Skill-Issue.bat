@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-And-Run-Skill-Issue.ps1" %*
if errorlevel 1 pause
