@echo off
chcp 65001 >nul
echo [DevTools2 Test Suite Runner]
where pwsh >nul 2>nul
if %errorlevel% equ 0 (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-all-tests.ps1"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "[scriptblock]::Create([System.IO.File]::ReadAllText('%~dp0run-all-tests.ps1', [System.Text.Encoding]::UTF8)).Invoke()"
)
exit /b %errorlevel%
