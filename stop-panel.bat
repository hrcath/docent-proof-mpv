@echo off
rem Turns OFF the settings web page. The player keeps running.
rem It comes back on the next time start-docent.bat runs (including at login).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0stop-panel.ps1"
echo.
pause
