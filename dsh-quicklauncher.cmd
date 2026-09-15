@echo off
setlocal
set "DSH_QUICKLAUNCHER_PS1=%~dp0dsh-quicklauncher.ps1"
if not exist "%DSH_QUICKLAUNCHER_PS1%" goto :dsh_quicklauncher_missing
where powershell.exe >nul 2>nul
if errorlevel 1 goto :dsh_quicklauncher_no_ps
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%DSH_QUICKLAUNCHER_PS1%" %*
set "DSH_QUICKLAUNCHER_EXIT=%ERRORLEVEL%"
endlocal & exit /b %DSH_QUICKLAUNCHER_EXIT%
:dsh_quicklauncher_no_ps
echo.
echo   [ERROR] Windows PowerShell was not found on PATH.
echo.
pause
endlocal & exit /b 1
:dsh_quicklauncher_missing
echo.
echo   [ERROR] dsh-quicklauncher.ps1 is missing next to this launcher.
echo           Expected at: %DSH_QUICKLAUNCHER_PS1%
echo.
pause
endlocal & exit /b 1
