@echo off
if exist "%~dp0launcher\bin\Release\net9.0-windows\DataCenterLauncher.exe" (
    start "" "%~dp0launcher\bin\Release\net9.0-windows\DataCenterLauncher.exe"
) else if exist "%~dp0dist\launcher_standalone\DataCenterLauncher.exe" (
    start "" "%~dp0dist\launcher_standalone\DataCenterLauncher.exe"
) else (
    start "" "%~dp0dist\launcher_v1.0.1\DataCenterLauncher.exe"
)
