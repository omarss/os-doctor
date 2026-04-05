@echo off
REM install.bat — Deploy Windows PowerShell profile + Optimize-Windows.ps1, then bootstrap.
REM
REM Usage: run install.bat from the repo directory (double-click or from cmd).

setlocal

if /I "%~1"=="--help" goto :usage
if /I "%~1"=="help" goto :usage
if "%~1"=="/?" goto :usage
if not "%~1"=="" goto :usage_error

set "REPO_DIR=%~dp0"
set "SRC=%REPO_DIR%shells\windows.ps1"
set "OPT_SRC=%REPO_DIR%optimize\windows.ps1"
set "OPT_DEST=%USERPROFILE%\Optimize-Windows.ps1"

for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set "STAMP=%%T"

echo ==^> Detected Windows

REM Check that the profile source exists
if not exist "%SRC%" (
    echo ERROR: shells\windows.ps1 not found in %REPO_DIR%
    pause
    exit /b 1
)

REM --- Deploy PowerShell profile ---
REM Determine the PowerShell profile path
for /f "delims=" %%P in ('powershell -NoProfile -Command "echo $PROFILE"') do set "PS_PROFILE=%%P"

REM Back up existing profile
if exist "%PS_PROFILE%" (
    echo ==^> Backing up existing profile to %PS_PROFILE%.bak.%STAMP%
    copy /Y "%PS_PROFILE%" "%PS_PROFILE%.bak.%STAMP%" >nul
)

REM Ensure the profile directory exists
for %%D in ("%PS_PROFILE%") do (
    if not exist "%%~dpD" mkdir "%%~dpD"
)

echo ==^> Installing shells\windows.ps1 to %PS_PROFILE%
copy /Y "%SRC%" "%PS_PROFILE%" >nul
echo   Done.

REM --- Deploy Optimize-Windows.ps1 ---
if exist "%OPT_SRC%" (
    if exist "%OPT_DEST%" (
        echo ==^> Backing up existing Optimize-Windows.ps1 to %OPT_DEST%.bak.%STAMP%
        copy /Y "%OPT_DEST%" "%OPT_DEST%.bak.%STAMP%" >nul
    )
    echo ==^> Copying optimize\windows.ps1 to %OPT_DEST%
    copy /Y "%OPT_SRC%" "%OPT_DEST%" >nul
    echo   Done.
) else (
    echo   optimize\windows.ps1 not found in repo - skipping.
)

REM --- Run bootstrap ---
echo ==^> Running Install-DevEnv (this will request admin elevation)...
powershell -NoProfile -ExecutionPolicy RemoteSigned -Command "& { . '%PS_PROFILE%'; Install-DevEnv }"

echo.
echo Bootstrap complete! Restart your terminal, then run doctor.
pause
exit /b 0

:usage
echo Usage: install.bat
echo.
echo Deploy the Windows PowerShell profile, back up any existing files with a
echo timestamped .bak suffix, and run Install-DevEnv.
exit /b 0

:usage_error
call :usage
exit /b 1
