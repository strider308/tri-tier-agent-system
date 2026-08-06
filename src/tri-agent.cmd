@echo off
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0tri-agent.ps1" %*
exit /b %ERRORLEVEL%
