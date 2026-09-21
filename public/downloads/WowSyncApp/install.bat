@echo off
setlocal
set INSTALLDIR=%~dp0
if "%INSTALLDIR:~-1%"=="\" set INSTALLDIR=%INSTALLDIR:~0,-1%

rem Make sure every command below actually runs from this folder, not
rem wherever Windows happened to start the process (e.g. C:\Windows\System32,
rem which is what "Run as administrator" or some shortcuts default to). Without
rem this, "npm install" below would try to write package-lock.json into
rem System32 and fail with EPERM.
cd /d "%INSTALLDIR%"

echo ============================================
echo   WoW Forever Tracker - background app setup
echo ============================================
echo.
echo Installing what it needs (this only happens once)...
echo.

call npm install
if %ERRORLEVEL% NEQ 0 (
  echo.
  echo Something went wrong. Do you have Node.js installed?
  echo Get it from https://nodejs.org, run the installer, then run this again.
  echo.
  pause
  exit /b 1
)

echo.
echo Creating a way to start it without a black window...

set LAUNCHER=%INSTALLDIR%\Launch WoW Forever Tracker.vbs
> "%LAUNCHER%" echo Set fso = CreateObject("Scripting.FileSystemObject")
>> "%LAUNCHER%" echo Set shell = CreateObject("WScript.Shell")
>> "%LAUNCHER%" echo shell.CurrentDirectory = "%INSTALLDIR%"
>> "%LAUNCHER%" echo shell.Run "node ""%INSTALLDIR%\sync.js""", 0, False

echo.
set /p AUTOSTART=Start this automatically every time you log into Windows? (Y/n):
if /I "%AUTOSTART%"=="n" goto skipstartup
copy /Y "%LAUNCHER%" "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Launch WoW Forever Tracker.vbs" >nul
echo Done - it'll start automatically from now on.
:skipstartup

echo.
echo Setup complete. Starting it now...
start "" "%LAUNCHER%"

echo.
echo A browser tab should open for a one-time setup - fill in the three
echo fields there. After that, look for its icon in the system tray near
echo the clock (click the little up-arrow if you don't see it right away).
echo.
pause
