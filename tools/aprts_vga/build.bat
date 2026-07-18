ca65 -t none demo.asm -o demo.o

ld65 -t none -S $3100 demo.o -o demo.bin
python ../ihex_gen.py demo.bin 3100 demo.hex