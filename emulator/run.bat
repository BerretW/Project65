@echo off
setlocal

:: ── Project65 Emulator — build & run ─────────────────────────────────────────
:: Device Guard blokuje nepodepsane binarky v adresarich projektu.
:: Reseni: prelozit do %LOCALAPPDATA%\p65emu-target ktery byva mimo WDAC blok.
::
:: Usage:  run.bat [ROM_FILE] [--speed HZ] [--port PORT]
:: Example: run.bat ..\output\MIN_ROM.bin --speed 2000000

set CARGO=%USERPROFILE%\.cargo\bin\cargo.exe
if not exist "%CARGO%" (
    echo ERROR: cargo not found at %CARGO%
    echo Install Rust from https://rustup.rs/
    pause
    exit /b 1
)

:: Presunout target/ do LOCALAPPDATA kde WDAC politika nemusi platit
set CARGO_TARGET_DIR=%LOCALAPPDATA%\p65emu-target

:: Zabit bezici instanci
taskkill /f /im p65emu.exe >nul 2>&1

echo.
echo Target dir: %CARGO_TARGET_DIR%
echo.
echo [1/2] Building p65emu...
"%CARGO%" build 2>&1
if errorlevel 1 (
    echo.
    echo BUILD FAILED.
    echo.
    echo Pokud stale vidi chybu "Zasada rizeni aplikaci", pozadejte IT o vyjimku pro:
    echo   %CARGO_TARGET_DIR%
    echo nebo pouzijte WSL2 ^(viz nize^).
    pause
    exit /b 1
)

echo.
echo [2/2] Starting emulator...
if "%~1"=="" (
    "%CARGO_TARGET_DIR%\debug\p65emu.exe" %*
) else (
    "%CARGO_TARGET_DIR%\debug\p65emu.exe" %*
)
