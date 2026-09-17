@echo off
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Transfer.ps1" -Mode Check
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Windows-Shift.ps1" -Mode Check
pause
