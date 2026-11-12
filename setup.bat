@echo off
rem One-time setup. Windows will ask for Administrator permission.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
