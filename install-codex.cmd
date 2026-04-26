@echo off
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
set "BOOTSTRAP_SCRIPT=%SCRIPT_DIR%scripts\bootstrap-codex-cli.ps1"
set "POWERSHELL_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

if not exist "%BOOTSTRAP_SCRIPT%" (
  echo [error] Bootstrap script was not found:
  echo         %BOOTSTRAP_SCRIPT%
  exit /b 1
)

if not exist "%POWERSHELL_EXE%" (
  echo [error] PowerShell was not found:
  echo         %POWERSHELL_EXE%
  exit /b 1
)

set "FORWARDED_ARGS="

:parse_args
if "%~1"=="" goto run_installer

if /I "%~1"=="--dry-run" (
  set "FORWARDED_ARGS=%FORWARDED_ARGS% -DryRun"
  shift
  goto parse_args
)

if /I "%~1"=="-h" goto show_help
if /I "%~1"=="--help" goto show_help
if /I "%~1"=="/?" goto show_help

set "FORWARDED_ARGS=%FORWARDED_ARGS% %1"
shift
goto parse_args

:run_installer
echo Starting Codex CLI bootstrap...
"%POWERSHELL_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%BOOTSTRAP_SCRIPT%" %FORWARDED_ARGS%
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
  echo.
  echo [error] Codex CLI bootstrap failed with exit code %EXIT_CODE%.
)

exit /b %EXIT_CODE%

:show_help
echo Usage:
echo   install-codex.cmd
echo   install-codex.cmd --dry-run
echo.
echo This launcher runs scripts\bootstrap-codex-cli.ps1 with ExecutionPolicy Bypass.
exit /b 0
