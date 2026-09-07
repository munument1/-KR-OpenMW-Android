@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0apply-openmw-051-shadow-grazing-angle-fix-v2.ps1"
set ERR=%ERRORLEVEL%
if not "%ERR%"=="0" (
  echo.
  echo Shadow grazing-angle V2 repair FAILED with exit code %ERR%.
  exit /b %ERR%
)
echo.
echo Shadow grazing-angle V2 repair completed successfully.
endlocal
