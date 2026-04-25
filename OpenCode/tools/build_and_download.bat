@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_windows.ps1" -CopyToDownloads %*
if errorlevel 1 pause
