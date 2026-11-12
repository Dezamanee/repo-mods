@echo off
chcp 65001 >nul
title R.E.P.O. ModPack Remover

echo This will remove mods from R.E.P.O. (BepInEx, winhttp.dll, doorstop files).
echo Game saves and settings are NOT touched.
echo.
choice /c YN /m "Continue"
if errorlevel 2 exit /b 0

powershell -NoProfile -Command "if (Test-Path '%~dp0uninstall.ps1') { Unblock-File -LiteralPath '%~dp0uninstall.ps1' }" >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1" %*
set RC=%ERRORLEVEL%

echo.
if not "%RC%"=="0" echo [ERROR] Removal failed with code %RC%.
echo Press any key to close...
pause >nul
exit /b %RC%
