@echo off
REM start-session.cmd - double-click launcher for start-session.ps1
REM Keeps the console open so you can read the checklist.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-session.ps1" %*
echo.
pause
