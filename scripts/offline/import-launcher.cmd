@echo off
rem ==========================================================================
rem DevTools2 offline import launcher (copied into the bundle as the Korean-named .cmd)
rem - ASCII only: cmd.exe reads .cmd files with the OEM code page.
rem - Re-runs itself as administrator (WSL features / WSL msi / scheduled task need it).
rem - Windows PowerShell 5.1 misreads UTF-8 (no BOM) Korean scripts from disk, so the
rem   import script is read as UTF-8 into memory and run from there (AGENTS.md rule 6).
rem ==========================================================================
setlocal
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "$global:DT2_BUNDLE='%~dp0'; Invoke-Expression ([System.IO.File]::ReadAllText('%~dp0import-devtools2-offline.ps1', [System.Text.Encoding]::UTF8))"
echo.
pause
