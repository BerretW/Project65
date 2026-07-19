@echo off
del demo.o demo.bin demo.hex 2>nul

ca65 -t none demo.asm -o demo.o || exit /b 1
ld65 -t none -S $3100 demo.o -o demo.bin || exit /b 1
python ../ihex_gen.py demo.bin 3100 demo.hex || exit /b 1