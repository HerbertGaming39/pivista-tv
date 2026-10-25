@echo off
rem Double-click launcher for the WSLg UI preview.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows-preview.ps1" %*
if errorlevel 1 pause
