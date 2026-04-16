@echo off
REM ============================================================
REM  P65 Chip Test (TMS9918A + SAA1099) - build skript
REM  Vystup: output\chiptest.bin  (presne 8192 B)
REM  Nahrani: bootloader 'w', spusteni 's'
REM ============================================================

for /f "delims=" %%i in ('where ca65 2^>nul') do set CA65=%%i
if not defined CA65 (
    echo CHYBA: ca65 nenalezeno v PATH.
    echo Nainstaluj cc65 a pridej do PATH.
    exit /b 1
)

if not exist "output" mkdir output 2>nul

del /Q .\output\*.* 2>nul

echo Sestavuji chiptest.asm...

ca65 --cpu 65c02 chiptest.asm -o output\chiptest.o -l output\chiptest.lst
if errorlevel 1 (
    echo CHYBA: ca65 selhalo.
    exit /b 1
)

ld65 -C chiptest.cfg -m output\chiptest.map output\chiptest.o -o output\chiptest.bin
if errorlevel 1 (
    echo CHYBA: ld65 selhalo.
    exit /b 1
)

for %%F in (output\chiptest.bin) do set FSIZE=%%~zF
if "%FSIZE%"=="8192" (
    echo.
    echo OK: output\chiptest.bin  [%FSIZE% B = 8192 B]
) else (
    echo VAROVANI: velikost binarky je %FSIZE% B, ocekavano 8192 B!
    exit /b 1
)

python bin2hex.py
if errorlevel 1 (
    python3 bin2hex.py
    if errorlevel 1 (
        echo VAROVANI: Python neni dostupny - Intel HEX nebyl vygenerovan.
    )
)

echo.
echo Postup nahrani (binary):
echo   1. Otevri serial terminal 19200 Bd, 8N1
echo   2. Bootloader menu: stiskni 'w'
echo   3. Odesli output\chiptest.bin jako raw binary
echo   4. Stiskni 's' pro spusteni
echo.
echo Postup nahrani (Intel HEX):
echo   1. Bootloader menu: stiskni 'h'
echo   2. Odesli output\chiptest.hex jako plain text
echo.
echo Ocekavany vystup na terminalu:
echo   TMS9918A: 3x OK (STATUS + VRAM $55 + VRAM $AA)
echo   SAA1099:  Zahraj stupnici C D E F G A, potvrd y/n
echo.
