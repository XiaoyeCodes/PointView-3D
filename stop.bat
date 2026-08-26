@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

set "PAUSE_AT_END=1"
set "EXIT_CODE=0"

:parse_args
if "%~1"=="" goto args_done
if /I "%~1"=="--no-pause" set "PAUSE_AT_END=0"
shift
goto parse_args

:args_done
if not exist ".server.pid" (
  echo Server is not running. No .server.pid file was found.
  goto finish
)

set "SERVER_PID="
set /p SERVER_PID=<".server.pid"
if not defined SERVER_PID (
  echo The PID file was empty. Cleaning it up.
  del /q ".server.pid" >nul 2>nul
  goto finish
)

powershell -NoProfile -Command "$p=Get-CimInstance Win32_Process -Filter 'ProcessId = !SERVER_PID!' -ErrorAction SilentlyContinue; if($p -and $p.Name -eq 'node.exe' -and $p.CommandLine -match 'server\.js'){exit 0}; exit 1" >nul 2>nul
if errorlevel 1 (
  echo No matching project server was found for PID !SERVER_PID!.
  echo The stale PID file has been removed.
  del /q ".server.pid" >nul 2>nul
  goto finish
)

echo Stopping server. PID: !SERVER_PID!...
powershell -NoProfile -Command "Stop-Process -Id !SERVER_PID! -Force -ErrorAction Stop; Wait-Process -Id !SERVER_PID! -ErrorAction SilentlyContinue" >nul 2>nul
if errorlevel 1 (
  echo [ERROR] The server could not be stopped.
  set "EXIT_CODE=1"
  goto finish
)

del /q ".server.pid" >nul 2>nul
echo Server stopped successfully.

:finish
if "!PAUSE_AT_END!"=="1" pause
exit /b !EXIT_CODE!
