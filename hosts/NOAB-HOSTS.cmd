@echo off
setlocal
title NewOutlookPatcher NOAB - Windows HOSTS
cd /d "%~dp0"

set "ACTION=%~1"

if /I "%ACTION%"=="Install" goto run
if /I "%ACTION%"=="Uninstall" goto run

echo Usage: NOAB-HOSTS.cmd Install ^| Uninstall
pause
exit /b 2

:run
echo ============================================================
echo  NewOutlookPatcher NOAB - HOSTS %ACTION%
echo ============================================================
echo.
echo This is a separate HOSTS permission step.
echo Windows will ask for Administrator approval.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0NOAB-Hosts.ps1" -Action %ACTION%
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (
  echo HOSTS action completed.
) else (
  echo HOSTS action failed with exit code %RC%.
)
echo.

exit /b %RC%
