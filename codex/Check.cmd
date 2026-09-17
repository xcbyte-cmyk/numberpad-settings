@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Transfer.ps1" -Mode Check
set "exitCode=%ERRORLEVEL%"
pause
exit /b %exitCode%
