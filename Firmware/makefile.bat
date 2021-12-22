del .\output\*.*

cd .\src
cc65 -t none -O --cpu 65C02 main.c
cc65 -t none -O --cpu 65c02 gameduino.c
cc65 -t none -O --cpu 65c02 sd.c
ca65 --cpu 65c02 main.s -o ..\output\main.o -l ..\lst\main.lst
ca65 --cpu 65c02 gameduino.s -o ..\output\gameduino.o -l ..\lst\gameduino.lst
ca65 --cpu 65c02 sd.s -o ..\output\sd.o -l ..\lst\sd.lst
ca65 --cpu 65c02 gd.asm -o ..\output\gd.o
ca65 --cpu 65c02 spi.asm -o ..\output\spi.o
ca65 --cpu 65c02 acia.asm -o ..\output\acia.o
ca65 --cpu 65c02 pckybd.asm -o ..\output\pckybd.o
ca65 --cpu 65c02 saa1099.asm -o ..\output\saa1099.o  -l ..\lst\saa1099.ls
ca65 --cpu 65c02 jumptable.asm -o ..\output\jumptable.o -l ..\lst\jumptable.lst
ca65 --cpu 65c02 routines.asm -o ..\output\routines.o -l ..\lst\routines.lst
ca65 --cpu 65c02 utils.asm -o ..\output\utils.o -l ..\lst\utils.lst
ca65 --cpu 65c02 zeropage.asm -o ..\output\zeropage.o -l ..\lst\zeropage.lst
ca65 --cpu 65c02 ewoz.asm -o ..\output\ewoz.o -l ..\lst\ewoz.lst
ca65 --cpu 65c02 vectors.asm -o ..\output\vectors.o -l ..\lst\vectors.lst
ca65 --cpu 65c02 interrupts.asm -o ..\output\interrupts.o -l ..\lst\interrupts.lst
ca65 --cpu 65c02 vdp.asm -o ..\output\vdp.o -l ..\lst\vdp.lst
ca65 --cpu 65c02 vdp_low.asm -o ..\output\vdp_low.o -l ..\lst\vdp_low.lst
ca65 --cpu 65c02 vdp_graph.asm -o ..\output\vdp_graph.o -l ..\lst\vdp_graph.lst


move *.s ..\output

cd ..\output

ld65 -C ..\config\APP_RAM_DISK.cfg -m ram.map main.o acia.o jumptable.o routines.o utils.o spi.o sd.o pckybd.o gameduino.o saa1099.o vdp.o vdp_low.o vdp_graph.o zeropage.o ewoz.o vectors.o interrupts.o ..\library\p65.lib -o ..\output\RAM.bin

ld65 -C ..\config\APP_ROM_DISK.cfg -m rom.map main.o acia.o jumptable.o routines.o utils.o spi.o sd.o pckybd.o gameduino.o saa1099.o vdp.o vdp_low.o vdp_graph.o zeropage.o ewoz.o vectors.o interrupts.o ..\library\p65.lib -o ..\output\ROM.bin
cd ..\emulator
Hbc56Emu_d.exe --rom ..\output\ROM.bin
