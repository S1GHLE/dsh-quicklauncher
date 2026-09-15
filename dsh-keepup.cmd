@echo off
setlocal
set "DSH_KEEPUP_PS1=%~dp0dsh-keepup.ps1"
if not exist "%DSH_KEEPUP_PS1%" goto :dsh_keepup_missing
where powershell.exe >nul 2>nul
if errorlevel 1 goto :dsh_keepup_no_ps
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%DSH_KEEPUP_PS1%" %*
set "DSH_KEEPUP_EXIT=%ERRORLEVEL%"
endlocal & exit /b %DSH_KEEPUP_EXIT%
:dsh_keepup_no_ps
echo.
echo   [ERROR] Windows PowerShell was not found on PATH.
echo.
pause
endlocal & exit /b 1
:dsh_keepup_missing
echo.
echo   [ERROR] dsh-keepup.ps1 is missing next to this launcher.
echo           Expected at: %DSH_KEEPUP_PS1%
echo.
pause
endlocal & exit /b 1
