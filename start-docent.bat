@echo off
rem ================================================================
rem  Docent-Proof MPV launcher
rem  Starts the settings web panel (hidden) and the full-screen player.
rem  The player restarts itself if it ever crashes. Ctrl+Q quits for good.
rem ================================================================

rem ---- Settings (change here only) --------------------------------
set "DOCENT_FOLDER=%USERPROFILE%\Videos\docent-proof"
set "PANEL_PORT=8080"
rem Leave PANEL_PIN empty for no PIN, or set e.g. 1234
set "PANEL_PIN="
rem -----------------------------------------------------------------

set "APP=%~dp0"
cd /d "%APP%"

if not exist "%APP%mpv\mpv.exe" (
  echo mpv.exe not found in "%APP%mpv\" - see README.md
  pause
  exit /b 1
)

set "PINARG="
if defined PANEL_PIN set "PINARG=-Pin %PANEL_PIN%"

rem Settings panel. If one is already running, this extra copy just exits.
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%APP%config-server.ps1" -Port %PANEL_PORT% -BaseDir "%DOCENT_FOLDER%" %PINARG%

rem If the player is already open (e.g. this was run just to turn the
rem settings page back on), don't open a second player.
tasklist /FI "IMAGENAME eq mpv.exe" 2>nul | find /I "mpv.exe" >nul
if not errorlevel 1 exit /b 0

:run
"%APP%mpv\mpv.exe" --config-dir="%APP%mpv-config" "--script-opts=docent-base_dir=%DOCENT_FOLDER%"
rem Exit code 0 = staff pressed Ctrl+Q. Anything else = crash, so restart.
if errorlevel 1 (
  timeout /t 3 /nobreak >nul
  goto run
)
