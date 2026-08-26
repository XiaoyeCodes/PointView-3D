@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

set "PAUSE_AT_END=1"
set "OPEN_BROWSER=1"
set "EXIT_CODE=0"
if not defined PORT set "PORT=3000"

:parse_args
if "%~1"=="" goto args_done
if /I "%~1"=="--no-pause" set "PAUSE_AT_END=0"
if /I "%~1"=="--no-open" set "OPEN_BROWSER=0"
shift
goto parse_args

:args_done
where node >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Node.js was not found in PATH.
  echo Double-click repair.bat to install or repair it automatically.
  set "EXIT_CODE=1"
  goto finish
)

where npm >nul 2>nul
if errorlevel 1 (
  echo [ERROR] npm was not found in PATH.
  echo Double-click repair.bat to repair Node.js and project dependencies.
  set "EXIT_CODE=1"
  goto finish
)

if not exist "package.json" (
  echo [ERROR] package.json was not found in:
  echo %CD%
  set "EXIT_CODE=1"
  goto finish
)

if not exist "node_modules\express\package.json" (
  echo Installing project dependencies...
  call npm install
  if errorlevel 1 (
    echo [ERROR] npm install failed.
    set "EXIT_CODE=1"
    goto finish
  )
)

if exist ".server.pid" (
  set "SERVER_PID="
  set /p SERVER_PID=<".server.pid"
  if defined SERVER_PID (
    powershell -NoProfile -Command "$p=Get-Process -Id !SERVER_PID! -ErrorAction SilentlyContinue; if($p -and $p.ProcessName -eq 'node'){exit 0}; exit 1" >nul 2>nul
    if not errorlevel 1 (
      echo Server is already running. PID: !SERVER_PID!
      echo URL: http://localhost:!PORT!
      if "!OPEN_BROWSER!"=="1" start "" "http://localhost:!PORT!"
      goto finish
    )
  )
  del /q ".server.pid" >nul 2>nul
)

powershell -NoProfile -Command "$c=Get-NetTCPConnection -LocalPort !PORT! -State Listen -ErrorAction SilentlyContinue; if($c){exit 0}; exit 1" >nul 2>nul
if not errorlevel 1 (
  echo [ERROR] Port !PORT! is already in use by another process.
  echo Stop that process or set a different PORT before starting.
  set "EXIT_CODE=1"
  goto finish
)

echo Starting server on port !PORT!...
set "SERVER_PID="
for /f "delims=" %%P in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $node=(Get-Command node).Source; $dir=(Get-Location).Path; $p=Start-Process -FilePath $node -ArgumentList 'server.js' -WorkingDirectory $dir -WindowStyle Hidden -PassThru; [Console]::Write($p.Id)"') do set "SERVER_PID=%%P"

if not defined SERVER_PID (
  echo [ERROR] The Node.js process could not be started.
  echo Run "npm start" in a terminal to see detailed errors.
  set "EXIT_CODE=1"
  goto finish
)

>".server.pid" echo !SERVER_PID!

powershell -NoProfile -Command "$end=(Get-Date).AddSeconds(15); do { try { $r=Invoke-WebRequest -UseBasicParsing -Uri 'http://localhost:!PORT!/' -TimeoutSec 2; if($r.StatusCode -eq 200){exit 0} } catch {}; Start-Sleep -Milliseconds 300 } while((Get-Date) -lt $end); exit 1" >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Server did not become ready within 15 seconds.
  echo Run "npm start" in a terminal to see detailed errors.
  taskkill /PID !SERVER_PID! /F >nul 2>nul
  del /q ".server.pid" >nul 2>nul
  set "EXIT_CODE=1"
  goto finish
)

echo Server started successfully. PID: !SERVER_PID!
echo URL: http://localhost:!PORT!
if "!OPEN_BROWSER!"=="1" start "" "http://localhost:!PORT!"

:finish
if "!PAUSE_AT_END!"=="1" pause
exit /b !EXIT_CODE!
