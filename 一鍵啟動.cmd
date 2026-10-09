@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
set "APP_PATH=%SCRIPT_DIR%PrinterBackup.exe"

if not exist "%APP_PATH%" (
  echo PrinterBackup.exe was not found. Extract the complete folder first.
  pause
  exit /b 1
)

start "" "%APP_PATH%"
endlocal
