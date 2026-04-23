ca65 -t none vga_test.asm -o vga_test.o

ld65 -t none -S $3100 vga_test.o -o vga_test.bin
python ../ihex_gen.py vga_test.bin 3100 vga_test.hex