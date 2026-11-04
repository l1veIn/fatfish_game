@echo off
rem Double-click to play the prototype.
rem Refresh imported assets and class_name registrations before running from source.
echo Preparing game...
"%~dp0tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path "%~dp0game" --import
if errorlevel 1 (
    echo Game preparation failed. See the error above.
    pause
    exit /b 1
)
start "" "%~dp0tools\godot\Godot_v4.7.2-stable_win64.exe" --path "%~dp0game" %*
