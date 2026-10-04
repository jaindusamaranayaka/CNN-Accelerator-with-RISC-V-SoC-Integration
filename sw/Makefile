CC      = riscv32-unknown-elf-gcc
OBJCOPY = riscv32-unknown-elf-objcopy

CFLAGS  = -mabi=ilp32 -march=rv32i -O2 -ffreestanding -nostdlib -Wall

all: firmware.hex

start.o: start.S
	$(CC) $(CFLAGS) -c start.S -o start.o

main.o: main.c
	$(CC) $(CFLAGS) -c main.c -o main.o

firmware.elf: start.o main.o sections.ld
	$(CC) $(CFLAGS) -Wl,-Bstatic,-T,sections.ld,--strip-debug start.o main.o -lgcc -o firmware.elf

firmware.bin: firmware.elf
	$(OBJCOPY) -O binary firmware.elf firmware.bin

firmware.hex: firmware.bin
	python3 -c "b=open('firmware.bin','rb').read(); h=open('firmware.hex','w'); [h.write('%02x\n' % x) for x in b]; h.close()"

clean:
	rm -f *.o *.elf *.bin *.hex
