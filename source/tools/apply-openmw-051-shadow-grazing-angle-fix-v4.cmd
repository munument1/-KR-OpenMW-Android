@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0apply-openmw-051-shadow-grazing-angle-fix-v4.ps1"
set ERR=%ERRORLEVEL%
if not "%ERR%"=="0" (
  echo.
  echo V4 patch failed with exit code %ERR%.
  exit /b %ERR%
)
echo.
echo V4 patch completed successfully.
