ca65 -t none vera_test.asm -o vera_test.o

ld65 -t none -S $3100 vera_test.o -o vera_test.bin
python ../ihex_gen.py vera_test.bin 3100 vera_test.hex