@echo off
chcp 65001 >nul
cd /d "%~dp0"
py -3 pipeline\build_release.py --web
if errorlevel 1 (
  echo 导出失败，请查看上方错误和 build 内的日志。
  pause
  exit /b 1
)
echo 候选包已生成在 build\candidate-*，包含独立源码快照、日志和 SHA-256 清单。
pause
