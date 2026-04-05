@echo off
REM install.bat — Deploy Windows PowerShell profile + Optimize-Windows.ps1, then bootstrap.
REM
REM Usage: run install.bat from the repo directory (double-click or from cmd).

setlocal

set "REPO_DIR=%~dp0"
set "SRC=%REPO_DIR%windows.ps1"
set "OPT_SRC=%REPO_DIR%Optimize-Windows.ps1"

echo ==> Detected Windows

REM Check that the profile source exists
if not exist "%SRC%" (
    echo ERROR: windows.ps1 not found in %REPO_DIR%
    pause
    exit /b 1
)

REM --- Deploy PowerShell profile ---
REM Determine the PowerShell profile path
for /f "delims=" %%P in ('powershell -NoProfile -Command "echo $PROFILE"') do set "PS_PROFILE=%%P"

REM Back up existing profile
if exist "%PS_PROFILE%" (
    echo ==> Backing up existing profile to %PS_PROFILE%.bak
    copy /Y "%PS_PROFILE%" "%PS_PROFILE%.bak" >nul
)

REM Ensure the profile directory exists
for %%D in ("%PS_PROFILE%") do (
    if not exist "%%~dpD" mkdir "%%~dpD"
)

echo ==> Installing windows.ps1 to %PS_PROFILE%
copy /Y "%SRC%" "%PS_PROFILE%" >nul
echo   Done.

REM --- Deploy Optimize-Windows.ps1 ---
if exist "%OPT_SRC%" (
    echo ==> Copying Optimize-Windows.ps1 to %USERPROFILE%\Optimize-Windows.ps1
    copy /Y "%OPT_SRC%" "%USERPROFILE%\Optimize-Windows.ps1" >nul
    echo   Done.
) else (
    echo   Optimize-Windows.ps1 not found in repo - skipping.
)

REM --- Run bootstrap ---
echo ==> Running Install-DevEnv (this will request admin elevation)...
powershell -NoProfile -ExecutionPolicy RemoteSigned -Command "& { . '%PS_PROFILE%'; Install-DevEnv }"

echo.
echo Bootstrap complete! Restart your terminal.
pause
