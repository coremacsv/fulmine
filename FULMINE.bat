@echo off
title Fulmine - ottimizzazione prestazioni
cd /d "%~dp0"

if not exist "%~dp0fulmine.ps1" (
    echo.
    echo   ERRORE: manca il file fulmine.ps1
    echo   Deve trovarsi nella stessa cartella di questo file.
    echo.
    pause
    exit /b 1
)

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo.
    echo   Fulmine ha bisogno dei permessi di amministratore per
    echo   cambiare piano energetico, servizi e alcune impostazioni.
    echo   Conferma la finestra di Windows che sta per aprirsi...
    echo.
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

mode con: cols=100 lines=45 >nul 2>&1

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0fulmine.ps1"
