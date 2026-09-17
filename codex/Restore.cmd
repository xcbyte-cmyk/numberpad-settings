@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Transfer.ps1" -Mode Restore
set "exitCode=%ERRORLEVEL%"
pause
exit /b %exitCode%
