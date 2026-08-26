@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

set "PAUSE_AT_END=1"
set "START_AFTER_REPAIR=1"
set "SAVE_PATH=1"
set "EXIT_CODE=0"
set "NODE_EXE="
set "NODE_DIR="
set "NPM_CMD="
set "NODE_WAS_IN_PATH=0"

:parse_args
if "%~1"=="" goto args_done
if /I "%~1"=="--no-pause" set "PAUSE_AT_END=0"
if /I "%~1"=="--no-start" set "START_AFTER_REPAIR=0"
if /I "%~1"=="--no-path-save" set "SAVE_PATH=0"
shift
goto parse_args

:args_done
echo PointView 3D repair tool
echo ========================

if not exist "package.json" (
  echo [ERROR] package.json was not found in:
  echo %CD%
  set "EXIT_CODE=1"
  goto finish
)

where node.exe >nul 2>nul
if not errorlevel 1 set "NODE_WAS_IN_PATH=1"

call :locate_node
if not defined NODE_EXE (
  echo Node.js was not found. Installing the official Node.js LTS package...
  call :install_node
  if errorlevel 1 (
    set "EXIT_CODE=1"
    goto finish
  )
  set "NODE_WAS_IN_PATH=0"
  call :locate_node
)

if not defined NODE_EXE (
  echo [ERROR] Node.js was installed but node.exe still could not be located.
  echo Restart Windows, then run repair.bat again.
  set "EXIT_CODE=1"
  goto finish
)

call :configure_node
if errorlevel 1 (
  set "EXIT_CODE=1"
  goto finish
)

"!NODE_EXE!" -e "process.exit(Number(process.versions.node.split('.')[0]) >= 18 ? 0 : 1)"
if errorlevel 1 (
  echo The installed Node.js version is older than version 18.
  echo Installing the current Node.js LTS package...
  call :install_node
  if errorlevel 1 (
    set "EXIT_CODE=1"
    goto finish
  )
  set "NODE_WAS_IN_PATH=0"
  call :locate_node
  call :configure_node
  if errorlevel 1 (
    set "EXIT_CODE=1"
    goto finish
  )
)

if "!NODE_WAS_IN_PATH!"=="0" if "!SAVE_PATH!"=="1" call :persist_node_path

echo.
echo Node.js: 
"!NODE_EXE!" --version
echo npm:
call "!NPM_CMD!" --version

echo.
echo Installing or repairing project dependencies...
call "!NPM_CMD!" install
if errorlevel 1 (
  echo [ERROR] npm install failed.
  echo Check the network connection and run repair.bat again.
  set "EXIT_CODE=1"
  goto finish
)

echo.
echo Repair completed successfully.
if "!START_AFTER_REPAIR!"=="1" (
  echo Starting PointView 3D...
  call "%~dp0start.bat" --no-pause
  if errorlevel 1 set "EXIT_CODE=1"
)
goto finish

:locate_node
set "NODE_EXE="
for /f "delims=" %%N in ('where node.exe 2^>nul') do if not defined NODE_EXE set "NODE_EXE=%%~fN"
if defined NODE_EXE exit /b 0

for %%D in ("%ProgramFiles%\nodejs" "%ProgramW6432%\nodejs" "%ProgramFiles(x86)%\nodejs" "%LOCALAPPDATA%\Programs\nodejs" "%LOCALAPPDATA%\Microsoft\WinGet\Links") do (
  if exist "%%~D\node.exe" if not defined NODE_EXE set "NODE_EXE=%%~D\node.exe"
)
exit /b 0

:configure_node
for %%D in ("!NODE_EXE!") do set "NODE_DIR=%%~dpD"
set "PATH=!NODE_DIR!;!PATH!"
set "NPM_CMD=!NODE_DIR!npm.cmd"
if not exist "!NPM_CMD!" (
  set "NPM_CMD="
  for /f "delims=" %%N in ('where npm.cmd 2^>nul') do if not defined NPM_CMD set "NPM_CMD=%%~fN"
)
if not defined NPM_CMD (
  echo [ERROR] npm.cmd was not found next to Node.js.
  echo Reinstall Node.js LTS and run repair.bat again.
  exit /b 1
)
exit /b 0

:persist_node_path
set "POINTVIEW_NODE_DIR=!NODE_DIR!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$dir=$env:POINTVIEW_NODE_DIR.TrimEnd('\'); $current=[Environment]::GetEnvironmentVariable('Path','User'); $parts=@($current -split ';' | ForEach-Object { $_.TrimEnd('\') }); if($parts -notcontains $dir){ $updated=if([string]::IsNullOrWhiteSpace($current)){$dir}else{$current.TrimEnd(';')+';'+$dir}; [Environment]::SetEnvironmentVariable('Path',$updated,'User') }" >nul 2>nul
if errorlevel 1 (
  echo [WARNING] Node.js works now, but its PATH entry could not be saved permanently.
  echo Run repair.bat as Administrator if the problem returns after restarting.
) else (
  echo Node.js was added to the user PATH.
)
exit /b 0

:install_node
where winget.exe >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Windows Package Manager was not found.
  echo The official Node.js download page will now open.
  echo Install the LTS version, then run repair.bat again.
  start "" "https://nodejs.org/en/download"
  exit /b 1
)

echo Windows may ask for Administrator permission during installation.
winget install --id OpenJS.NodeJS.LTS --exact --source winget --silent --accept-source-agreements --accept-package-agreements
if errorlevel 1 (
  echo [ERROR] Node.js LTS installation failed.
  echo Check the messages above, then run repair.bat again.
  exit /b 1
)

if exist "%ProgramFiles%\nodejs\node.exe" set "NODE_EXE=%ProgramFiles%\nodejs\node.exe"
exit /b 0

:finish
echo.
if "!PAUSE_AT_END!"=="1" pause
exit /b !EXIT_CODE!
