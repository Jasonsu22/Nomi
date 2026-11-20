@echo off
rem Double-click to run Nomi's Phase 0 measurements. Add -Quick for a 10-minute run.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-phase0.ps1" %*
pause
