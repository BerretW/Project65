@echo on
REM ============================================================
REM  AppartusOS - build script
REM
REM  Obsah: ACIA + EWOZ + ihex + AppartusOS shell + RAMDisk
REM  Vystup: output/APPARTUS_OS.bin  (8 KB, zapisuje se do EEPROM)
REM
REM  Pozadavky: cc65 (cc65, ca65, ld65) na PATH
REM ============================================================

REM Zjisti cestu ke cc65 knihovnam
for /f "tokens=*" %%i in ('where cc65') do set CC65_FULL=%%i
for %%i in ("%CC65_FULL%") do set CC65_BINDIR=%%~dpi
set CC65_LIB=%CC65_BINDIR%..\lib\none.lib
echo Pouzivam cc65 knihovnu: %CC65_LIB%

REM Vytvor vystupni adresare
if not exist "output" mkdir output
if not exist "lst"    mkdir lst

REM Vycisti predchozi build
del /Q .\output\*.*  2>nul

cd .\src

REM ----------------------------------------------------------
REM  Kompilace C souboru
REM ----------------------------------------------------------
cc65 -t none -O --cpu 65C02 main_appartus.c
if errorlevel 1 ( echo CHYBA: cc65 main_appartus.c & cd .. & exit /b 1 )

REM ----------------------------------------------------------
REM  Assembler - spolecne moduly
REM ----------------------------------------------------------
ca65 --cpu 65c02 crt0_p65.asm       -o ..\output\crt0_p65.o       -l ..\lst\crt0_p65.lst
if errorlevel 1 ( echo CHYBA: ca65 crt0_p65.asm & cd .. & exit /b 1 )

ca65 --cpu 65c02 main_appartus.s    -o ..\output\main_appartus.o   -l ..\lst\main_appartus.lst
if errorlevel 1 ( echo CHYBA: ca65 main_appartus.s & cd .. & exit /b 1 )

ca65 --cpu 65c02 stubs_min.asm      -o ..\output\stubs_min.o       -l ..\lst\stubs_min.lst
if errorlevel 1 ( echo CHYBA: ca65 stubs_min.asm & cd .. & exit /b 1 )

ca65 --cpu 65c02 acia.asm           -o ..\output\acia.o            -l ..\lst\acia.lst
if errorlevel 1 ( echo CHYBA: ca65 acia.asm & cd .. & exit /b 1 )

ca65 --cpu 65c02 ewoz.asm           -o ..\output\ewoz.o            -l ..\lst\ewoz.lst
if errorlevel 1 ( echo CHYBA: ca65 ewoz.asm & cd .. & exit /b 1 )

ca65 --cpu 65c02 ihex.asm           -o ..\output\ihex.o            -l ..\lst\ihex.lst
if errorlevel 1 ( echo CHYBA: ca65 ihex.asm & cd .. & exit /b 1 )

ca65 --cpu 65c02 utils.asm          -o ..\output\utils.o           -l ..\lst\utils.lst
if errorlevel 1 ( echo CHYBA: ca65 utils.asm & cd .. & exit /b 1 )

ca65 --cpu 65c02 routines.asm       -o ..\output\routines.o        -l ..\lst\routines.lst
if errorlevel 1 ( echo CHYBA: ca65 routines.asm & cd .. & exit /b 1 )

ca65 --cpu 65c02 vectors.asm        -o ..\output\vectors.o
if errorlevel 1 ( echo CHYBA: ca65 vectors.asm & cd .. & exit /b 1 )

ca65 --cpu 65c02 interrupts.asm     -o ..\output\interrupts.o      -l ..\lst\interrupts.lst
if errorlevel 1 ( echo CHYBA: ca65 interrupts.asm & cd .. & exit /b 1 )

ca65 --cpu 65c02 zeropage.asm       -o ..\output\zeropage.o
if errorlevel 1 ( echo CHYBA: ca65 zeropage.asm & cd .. & exit /b 1 )

ca65 --cpu 65c02 jumptable.asm      -o ..\output\jumptable.o       -l ..\lst\jumptable.lst
if errorlevel 1 ( echo CHYBA: ca65 jumptable.asm & cd .. & exit /b 1 )

REM ----------------------------------------------------------
REM  Assembler - AppartusOS moduly
REM ----------------------------------------------------------
ca65 --cpu 65c02 os\appartus_zp.asm          -o ..\output\appartus_zp.o         -l ..\lst\appartus_zp.lst
if errorlevel 1 ( echo CHYBA: ca65 appartus_zp.asm & cd .. & exit /b 1 )

ca65 --cpu 65c02 os\appartus_ramdisk.asm     -o ..\output\appartus_ramdisk.o    -l ..\lst\appartus_ramdisk.lst
if errorlevel 1 ( echo CHYBA: ca65 appartus_ramdisk.asm & cd .. & exit /b 1 )

ca65 --cpu 65c02 os\appartus_fileio.asm      -o ..\output\appartus_fileio.o     -l ..\lst\appartus_fileio.lst
if errorlevel 1 ( echo CHYBA: ca65 appartus_fileio.asm & cd .. & exit /b 1 )

ca65 --cpu 65c02 os\appartus_shell.asm       -o ..\output\appartus_shell.o      -l ..\lst\appartus_shell.lst
if errorlevel 1 ( echo CHYBA: ca65 appartus_shell.asm & cd .. & exit /b 1 )

ca65 --cpu 65c02 os\appartus_jmptbl_ext.asm  -o ..\output\appartus_jmptbl_ext.o -l ..\lst\appartus_jmptbl_ext.lst
if errorlevel 1 ( echo CHYBA: ca65 appartus_jmptbl_ext.asm & cd .. & exit /b 1 )

REM Presun vygenerovane .s soubory
move /Y *.s ..\output  1>nul

cd ..\output

REM ----------------------------------------------------------
REM  Linker
REM  Poradi objektu:
REM    1. crt0 (definuje _init = RESET vektor)
REM    2. main_appartus
REM    3. spolecne moduly
REM    4. jumptable (JMPTBL od $FF00)
REM    5. appartus_jmptbl_ext (JMPTBL pokracovani od $FF33)
REM    6. OS moduly
REM    7. none.lib
REM ----------------------------------------------------------
ld65 -C ..\config\appartus_os.cfg ^
     -m appartus_os.map ^
     crt0_p65.o ^
     main_appartus.o ^
     stubs_min.o ^
     acia.o ^
     ewoz.o ^
     ihex.o ^
     utils.o ^
     routines.o ^
     vectors.o ^
     interrupts.o ^
     zeropage.o ^
     jumptable.o ^
     appartus_jmptbl_ext.o ^
     appartus_zp.o ^
     appartus_ramdisk.o ^
     appartus_fileio.o ^
     appartus_shell.o ^
     %CC65_LIB% ^
     -o APPARTUS_OS.bin
if errorlevel 1 ( echo CHYBA: ld65 linker & cd .. & exit /b 1 )

cd ..

echo.
echo ============================================================
echo  Hotovo: Firmware\output\APPARTUS_OS.bin
echo  Map:    Firmware\output\appartus_os.map
echo ============================================================
