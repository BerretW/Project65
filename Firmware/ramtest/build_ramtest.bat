@echo off
REM ============================================================
REM  P65 RAM Test – build skript
REM  Vystup: output\ramtest.bin  (přesně 8192 B)
REM  Nahrání: bootloader 'w', spuštění 's'
REM ============================================================

REM Zjisti cestu ke cc65 nástrojům automaticky (stejně jako build_minimal.bat)
for /f "delims=" %%i in ('where ca65 2^>nul') do set CA65=%%i
if not defined CA65 (
    echo CHYBA: ca65 nenalezeno v PATH.
    echo Nainstaluj cc65 a pridej do PATH.
    exit /b 1
)

REM Vytvoř výstupní adresář pokud neexistuje
if not exist "output" mkdir output 2>nul

REM Vyčisti předchozí build
del /Q .\output\*.* 2>nul

echo Sestavuji ramtest.asm...

REM --- Assembler ---
ca65 --cpu 65c02 ramtest.asm -o output\ramtest.o -l output\ramtest.lst
if errorlevel 1 (
    echo CHYBA: ca65 selhalo.
    exit /b 1
)

REM --- Linker ---
ld65 -C ramtest.cfg -m output\ramtest.map output\ramtest.o -o output\ramtest.bin
if errorlevel 1 (
    echo CHYBA: ld65 selhalo.
    exit /b 1
)

REM Ověř velikost binárky (musí být přesně 8192 B)
for %%F in (output\ramtest.bin) do set FSIZE=%%~zF
if "%FSIZE%"=="8192" (
    echo.
    echo OK: output\ramtest.bin  [%FSIZE% B = 8192 B]
) else (
    echo VAROVANI: velikost binárky je %FSIZE% B, očekáváno 8192 B!
    exit /b 1
)

REM --- Intel HEX ---
python bin2hex.py
if errorlevel 1 (
    python3 bin2hex.py
    if errorlevel 1 (
        echo VAROVANI: Python neni dostupny – Intel HEX nebyl vygenerovan.
    )
)

echo.
echo Postup nahrani ^(binary^):
echo   1. Otevri serial terminal 19200 Bd, 8N1
echo   2. Bootloader menu: stiskni 'w'
echo   3. Odesli output\ramtest.bin jako raw binary
echo.
echo Postup nahrani ^(Intel HEX^):
echo   1. Bootloader menu: stiskni 'i' ^(ihex loader^)
echo   2. Odesli output\ramtest.hex jako plain text
