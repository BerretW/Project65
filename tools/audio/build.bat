@echo off
del hello.o hello.bin hello.hex 2>nul


ca65 -t none --cpu 65C02 hello.asm -o hello.o || exit /b 1
ca65 -t none --cpu 65C02 aprts_audio.asm -o audio.o || exit /b 1
ld65 -t none -S $3000 hello.o audio.o -o hello.bin || exit /b 1
python ../ihex_gen.py hello.bin 3000 hello.hex || exit /b 1