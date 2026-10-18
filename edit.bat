@echo off
rem Double-click to open the project in the Godot editor.
start "" "%~dp0tools\godot\Godot_v4.7.2-stable_win64.exe" --editor --path "%~dp0game"
