@echo off
setlocal EnableExtensions
set "POINTVIEW_PAUSE=1"
set "POINTVIEW_NO_OPEN="
:parse
if "%~1"=="" goto launch
if /I "%~1"=="--no-pause" set "POINTVIEW_PAUSE=0"
if /I "%~1"=="--no-open" set "POINTVIEW_NO_OPEN=-NoOpen"
shift
goto parse

:launch
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\start.ps1" %POINTVIEW_NO_OPEN%
set "POINTVIEW_EXIT=%ERRORLEVEL%"
if "%POINTVIEW_PAUSE%"=="1" pause
exit /b %POINTVIEW_EXIT%
