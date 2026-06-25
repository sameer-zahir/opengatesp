@echo off
setlocal
rem OpenGateSP - double-click launcher. Finds PowerShell 7 and opens the app.
set "HERE=%~dp0"
where pwsh >nul 2>nul
if %ERRORLEVEL%==0 (
    pwsh -STA -NoProfile -ExecutionPolicy Bypass -File "%HERE%tools\Launch.ps1"
) else (
    echo.
    echo PowerShell 7 ^(pwsh^) was not found on this PC.
    echo Install it once from https://aka.ms/powershell  or run:
    echo     winget install Microsoft.PowerShell
    echo.
    pause
)
endlocal
