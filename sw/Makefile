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
	python3 -c "b=open('firmware.bin','rb').read(); b+=b'\0'*(65536-len(b)); h=open('firmware.hex','w'); [h.write('%08x\n' % int.from_bytes(b[i:i+4], 'little')) for i in range(0, len(b), 4)]; h.close(); [open(f'firmware_{k}.hex','w').write(''.join('%02x\n'%b[i] for i in range(k,len(b),4))) for k in range(4)]"

clean:
	rm -f *.o *.elf *.bin *.hex
