@echo off
powershell.exe -NoProfile -File "%~dp0tool\Get-CameraSetup.ps1" %*
pause
