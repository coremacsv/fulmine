@echo off
title Fulmine - crea collegamento sul Desktop
cd /d "%~dp0"

if not exist "%~dp0FULMINE.bat" (
    echo.
    echo   ERRORE: manca FULMINE.bat in questa cartella.
    echo.
    pause
    exit /b 1
)

echo.
echo   Creo un collegamento a Fulmine sul tuo Desktop, con l'icona.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$s = (New-Object -ComObject WScript.Shell); $d = [Environment]::GetFolderPath('Desktop');" ^
  "$l = $s.CreateShortcut((Join-Path $d 'Fulmine.lnk'));" ^
  "$l.TargetPath = '%~dp0FULMINE.bat';" ^
  "$l.WorkingDirectory = '%~dp0';" ^
  "$l.Description = 'Fulmine - ottimizzazione prestazioni per Windows';" ^
  "if (Test-Path '%~dp0fulmine.ico') { $l.IconLocation = '%~dp0fulmine.ico' };" ^
  "$l.Save();" ^
  "Write-Host ''; Write-Host '  Fatto: trovi Fulmine sul Desktop.' -ForegroundColor Green"

echo.
pause
