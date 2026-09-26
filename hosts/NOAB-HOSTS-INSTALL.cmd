@echo off
setlocal EnableExtensions
title NewOutlookPatcher NOAB - Install HOSTS block
cd /d "%~dp0"

echo.
echo ============================================================
echo  INSTALL OUTLOOK HOSTS AD BLOCKING
echo ============================================================
echo.
echo Windows will request Administrator approval.
echo NOAB will not change HOSTS ownership or ACLs.
echo.
echo Press any key to continue, or close this window to cancel.
pause >nul

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0NOAB-Hosts.ps1" -Action Install
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (
    echo ============================================================
    echo  HOSTS INSTALL COMPLETED
    echo ============================================================
    goto done
)

if "%RC%"=="23" (
    echo ============================================================
    echo  KASPERSKY IS PROTECTING THE WINDOWS HOSTS FILE
    echo ============================================================
    echo.
    echo Pause Kaspersky protection temporarily, run this action again,
    echo then re-enable Kaspersky protection immediately afterwards.
    goto failed
)

if "%RC%"=="24" (
    echo ============================================================
    echo  HOSTS IS PROTECTED BY SECURITY SOFTWARE
    echo ============================================================
    echo.
    echo No Kaspersky filter was detected. Another security product
    echo or file-system filter may be blocking the HOSTS file.
    goto failed
)

echo ============================================================
echo  HOSTS INSTALL FAILED - EXIT CODE %RC%
echo ============================================================

:failed
echo.
echo Press any key to close.
pause >nul
exit /b %RC%

:done
echo.
echo Press any key to close.
pause >nul
exit /b 0
