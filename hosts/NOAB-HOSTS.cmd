@echo off
setlocal EnableExtensions
title NewOutlookPatcher NOAB - Windows HOSTS Permission

set "ACTION=%~1"

if /I "%ACTION%"=="Install" goto valid
if /I "%ACTION%"=="Uninstall" goto valid

echo.
echo Usage:
echo   NOAB-HOSTS.cmd Install
echo   NOAB-HOSTS.cmd Uninstall
echo.
pause
exit /b 2

:valid
set "NOAB_ADMIN_PS=%~dp0NOAB-Hosts-Admin.ps1"
set "NOAB_ACTION=%ACTION%"

if not exist "%NOAB_ADMIN_PS%" (
    echo.
    echo ERROR: NOAB-Hosts-Admin.ps1 was not found.
    echo Expected:
    echo   %NOAB_ADMIN_PS%
    echo.
    pause
    exit /b 3
)

echo.
echo ============================================================
echo  NewOutlookPatcher NOAB - HOSTS %ACTION%
echo ============================================================
echo.
echo A separate Administrator approval is required to modify:
echo   %SystemRoot%\System32\drivers\etc\hosts
echo.
echo Windows will now show a SECOND UAC prompt.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$script=$env:NOAB_ADMIN_PS; $action=$env:NOAB_ACTION; $a='-NoProfile -ExecutionPolicy Bypass -File ""' + $script + '"" -Action ' + $action; try { $p=Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $a -PassThru -Wait -ErrorAction Stop; exit $p.ExitCode } catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 5 }"

set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (
    echo HOSTS %ACTION% completed successfully.
) else (
    echo HOSTS %ACTION% failed with exit code %RC%.
    echo.
    echo The elevated helper could not complete the HOSTS operation.
    echo Review the message in the Administrator PowerShell window.
    echo.
    pause
)

exit /b %RC%
