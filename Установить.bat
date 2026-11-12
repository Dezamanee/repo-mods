@echo off
chcp 65001 >nul
title R.E.P.O. ModPack installer
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
