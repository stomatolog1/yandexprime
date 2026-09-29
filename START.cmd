@echo off
setlocal EnableExtensions
cd /d "%~dp0"

:: Run the PowerShell controller as Administrator
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process PowerShell.exe -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File ""%~dp0Install.ps1""'"

endlocal
