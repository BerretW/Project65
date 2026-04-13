@echo on
REM ============================================================
REM  P65 Minimal Bootloader - build script
REM  Obsah: ACIA (serial) + EWOZ (WozMon) + seriovy bootloader
REM  Zadna zavislost na VDP / PS2 / SPI / SD / Gameduino / SAA
REM
REM  Knihovna: pouziva none.lib z instalace cc65 + vlastni crt0_p65.asm
REM  -> zadna zavislost na externim p65.lib
REM ============================================================

REM Zjisti cestu ke cc65 knihovnam automaticky
for /f "delims=" %%i in ('where cc65') do set CC65_BIN=%%i
for %%i in ("%CC65_BIN%") do set CC65_DIR=%%~dpi..
set CC65_LIB=%CC65_DIR%\lib\none.lib

echo Pouzivam cc65 knihovnu: %CC65_LIB%

REM Vytvor vystupni adresare pokud neexistuji
if not exist "output" mkdir output
if not exist "lst"    mkdir lst

REM Vycisti predchozi build
del /Q .\output\*.*  2>nul

cd .\src

REM ----------------------------------------------------------
REM  Kompilace C souboru (cc65)
REM ----------------------------------------------------------
cc65 -t none -O --cpu 65C02 main_min.c
if errorlevel 1 ( echo CHYBA: cc65 main_min.c & cd .. & exit /b 1 )

REM ----------------------------------------------------------
REM  Assembler - crt0 + minimalni sada modulu (ca65)
REM ----------------------------------------------------------
ca65 --cpu 65c02 crt0_p65.asm   -o ..\output\crt0_p65.o    -l ..\lst\crt0_p65.lst
if errorlevel 1 ( echo CHYBA: ca65 crt0_p65.asm & cd .. & exit /b 1 )

ca65 --cpu 65c02 main_min.s     -o ..\output\main_min.o    -l ..\lst\main_min.lst
if errorlevel 1 ( echo CHYBA: ca65 main_min.s & cd .. & exit /b 1 )

ca65 --cpu 65c02 stubs_min.asm  -o ..\output\stubs_min.o   -l ..\lst\stubs_min.lst
if errorlevel 1 ( echo CHYBA: ca65 stubs_min.asm & cd .. & exit /b 1 )

ca65 --cpu 65c02 acia.asm       -o ..\output\acia.o        -l ..\lst\acia.lst
if errorlevel 1 ( echo CHYBA: ca65 acia.asm & cd .. & exit /b 1 )

ca65 --cpu 65c02 ewoz.asm       -o ..\output\ewoz.o        -l ..\lst\ewoz.lst
if errorlevel 1 ( echo CHYBA: ca65 ewoz.asm & cd .. & exit /b 1 )

ca65 --cpu 65c02 utils.asm      -o ..\output\utils.o       -l ..\lst\utils.lst
if errorlevel 1 ( echo CHYBA: ca65 utils.asm & cd .. & exit /b 1 )

ca65 --cpu 65c02 jumptable.asm  -o ..\output\jumptable.o   -l ..\lst\jumptable.lst
if errorlevel 1 ( echo CHYBA: ca65 jumptable.asm & cd .. & exit /b 1 )

ca65 --cpu 65c02 routines.asm   -o ..\output\routines.o    -l ..\lst\routines.lst
if errorlevel 1 ( echo CHYBA: ca65 routines.asm & cd .. & exit /b 1 )

ca65 --cpu 65c02 vectors.asm    -o ..\output\vectors.o
if errorlevel 1 ( echo CHYBA: ca65 vectors.asm & cd .. & exit /b 1 )

ca65 --cpu 65c02 interrupts.asm -o ..\output\interrupts.o  -l ..\lst\interrupts.lst
if errorlevel 1 ( echo CHYBA: ca65 interrupts.asm & cd .. & exit /b 1 )

ca65 --cpu 65c02 zeropage.asm   -o ..\output\zeropage.o
if errorlevel 1 ( echo CHYBA: ca65 zeropage.asm & cd .. & exit /b 1 )

ca65 --cpu 65c02 ihex.asm       -o ..\output\ihex.o        -l ..\lst\ihex.lst
if errorlevel 1 ( echo CHYBA: ca65 ihex.asm & cd .. & exit /b 1 )

REM Presun vygenerovane .s soubory do output
move /Y *.s ..\output  1>nul

cd ..\output

REM ----------------------------------------------------------
REM  Linker (ld65)
REM  Poradi: crt0 musi byt prvni (definuje _init pro RESET vektor)
REM ----------------------------------------------------------
ld65 -C ..\config\MIN_ROM.cfg ^
     -m min_rom.map ^
     crt0_p65.o ^
     main_min.o ^
     acia.o ^
     ewoz.o ^
     utils.o ^
     jumptable.o ^
     routines.o ^
     vectors.o ^
     interrupts.o ^
     zeropage.o ^
     stubs_min.o ^
     ihex.o ^
     %CC65_LIB% ^
     -o MIN_ROM.bin
if errorlevel 1 ( echo CHYBA: ld65 linker & cd .. & exit /b 1 )

cd ..

echo.
echo ============================================================
echo  Hotovo: Firmware\output\MIN_ROM.bin
echo  Knihovna: %CC65_LIB%
echo  Mapovaci soubor: Firmware\output\min_rom.map
echo ============================================================
