@echo off
setlocal
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Update-SmartDustbin.ps1" %*
if errorlevel 1 (
  echo.
  echo Update failed. Read the error above, then try again.
  exit /b 1
)
endlocal
