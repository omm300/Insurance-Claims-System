@echo off
REM Windows launcher: runs the JCL emulation script inside WSL (Ubuntu).
REM Prerequisite (once, inside WSL):  sudo apt-get install gnucobol
set "PROJECT=%~dp0.."
for %%I in ("%PROJECT%") do set "PROJECT=%%~fI"
set "DRIVE=%PROJECT:~0,1%"
set "REST=%PROJECT:~2%"
set "REST=%REST:\=/%"
for %%L in (a b c d e f g h i j k l m n o p q r s t u v w x y z) do if /I "%DRIVE%"=="%%L" set "DRIVE=%%L"
wsl -d Ubuntu -- bash -c "cd '/mnt/%DRIVE%%REST%' && bash scripts/run_batch.sh"
echo.
echo Job finished with exit code %ERRORLEVEL%  (0 = clean, 4 = completed with exceptions)
pause
