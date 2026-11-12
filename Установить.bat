@echo off
chcp 65001 >nul
title R.E.P.O. ModPack Installer

powershell -NoProfile -Command "if (Test-Path '%~dp0install.ps1') { Unblock-File -LiteralPath '%~dp0install.ps1' }" >nul 2>&1

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
set RC=%ERRORLEVEL%

if not "%RC%"=="0" (
    echo.
    echo [ERROR] Installation failed with code %RC%.
    echo If it says "Access denied", close this window, right-click this file
    echo and choose "Run as administrator".
    echo Press any key to close...
    pause >nul
    exit /b %RC%
)

echo.
echo Press any key to close...
pause >nul
exit /b 0
