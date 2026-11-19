@echo off
if exist "%~dp0dist\launcher_standalone\DataCenterLauncher.exe" (
    start "" "%~dp0dist\launcher_standalone\DataCenterLauncher.exe"
) else (
    start "" "%~dp0launcher\bin\Release\net9.0-windows\DataCenterLauncher.exe"
)
