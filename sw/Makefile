# Compiler settings for RISC-V 32-bit integer architecture
CC = riscv32-unknown-elf-gcc
OBJCOPY = riscv32-unknown-elf-objcopy

CFLAGS = -mabi=ilp32 -march=rv32i -O2 -ffreestanding -nostdlib

all: firmware.hex

# Compile assembly boot code
start.o: start.S
	$(CC) $(CFLAGS) -c start.S -o start.o

# Compile main C code
main.o: main.c
	$(CC) $(CFLAGS) -c main.c -o main.o

# Link everything together into an ELF file using our memory map
firmware.elf: start.o main.o sections.ld
	$(CC) $(CFLAGS) -Wl,-Bstatic,-T,sections.ld,--strip-debug start.o main.o -lgcc -o firmware.elf

# Convert ELF to raw binary
firmware.bin: firmware.elf
	$(OBJCOPY) -O binary firmware.elf firmware.bin

# Convert binary to Verilog hex format (which Quartus $readmemh can read)
firmware.hex: firmware.bin
	# We use python to create a standard verilog hex file from binary
	python3 -c "import sys; b=open('firmware.bin','rb').read(); h=open('firmware.hex','w'); [h.write('%02x\n' % x) for x in b]; h.close()"

clean:
	rm -f *.o *.elf *.bin *.hex
