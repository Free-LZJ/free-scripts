@echo off
rem Usage: obsidian-init [vault-path] [-SharedConfig <shared .obsidian>]
rem Prefers PowerShell 7 and falls back to Windows PowerShell 5.1.
where pwsh >nul 2>nul
if %ERRORLEVEL%==0 (
  pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0obsidian-init.ps1" %*
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0obsidian-init.ps1" %*
)
