@echo off
chcp 65001 >nul
REM 重新导出 Windows 版（单个 exe）和网页版，输出在 build\ 目录
cd /d "%~dp0"
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path game --export-release "Windows" ../build/windows/FatFish.exe
"tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path game --export-release "Web" ../build/web/index.html
copy /y "build\说明.txt" "build\windows\说明.txt" >nul
powershell -NoProfile -Command "Compress-Archive -Force -Path build\web\* -DestinationPath build\FatFish_web.zip"
powershell -NoProfile -Command "Compress-Archive -Force -Path build\windows\* -DestinationPath build\FatFish_windows.zip"
echo 导出完成：build\FatFish_windows.zip（exe+说明）和 build\FatFish_web.zip（网页版）
pause
