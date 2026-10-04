# CNN Accelerator on FPGA: Complete System Guide

This guide provides a comprehensive overview of the CNN Accelerator project, explaining how the hardware and software components interact, the physical setup required, and the step-by-step workflow to get the entire system running.

---

## 1. The Big Picture: Hardware & Software Architecture

The project implements a **System-on-Chip (SoC)** on an FPGA. At its core is a **PicoRV32** processor (a 32-bit RISC-V soft-core) that runs C firmware. This processor coordinates with custom hardware peripherals (UART, GPIO) and a dedicated CNN Hardware Accelerator via an internal memory-mapped interconnect.

### 1.1 Hardware Components (`rtl/` folder)
*   **`soc_top.sv`**: The top-level System-on-Chip module. It wires everything together. It instantiates the PicoRV32 CPU, the Interconnect, RAM, and the peripherals (UART, GPIO, and accelerator stubs).
*   **`picorv32.v`**: The RISC-V CPU core that executes the compiled C code.
*   **`soc_interconnect.sv`**: The memory router. When the CPU asks to read or write a specific memory address, this module routes that request to the correct peripheral (RAM, UART, GPIO, or the CNN Accelerator buffers).
*   **`uart_peripheral.sv` & `gpio_peripheral.sv`**: Interfaces for communicating with the outside world. UART talks to the laptop, and GPIO drives the board's 7-segment displays or LEDs.
*   **`cnn_acc.sv`**: The custom CNN hardware accelerator. It contains a multi-stage pipeline: Feature Extraction -> ReLU -> Pooling -> Flatten -> Normalize -> Classification. 
*   *(Other files like `board_test.v`, `lineBufferAXI.sv`, `slidingWindowAXI.sv` are supporting modules for testing and data movement).*

### 1.2 Memory Map
The hardware uses a specific memory map, meaning the C code communicates with hardware by writing to specific addresses:
*   `0x00000000`: Main RAM (64KB) - where the C firmware lives and executes.
*   `0x10000000`: UART (Serial communication)
*   `0x20000000`: Image BRAM (Memory buffer where the PC sends the image)
*   `0x30000000`: Output BRAM (Where the hardware accelerator places its results)
*   `0x40000000`: MAC Control (Register to tell the hardware accelerator to start)
*   `0x50000000`: GPIO (Output to physical LEDs/7-Segment displays)

### 1.3 Software Components (`sw/` folder)
*   **`start.S`**: Assembly boot code. It runs immediately when the FPGA turns on, sets up the stack pointer in RAM, and jumps to your C `main()` function.
*   **`main.c`**: The "brain" of the SoC. It waits for an image from the PC via UART, saves it to the Image BRAM, triggers the hardware accelerator, reads the result, outputs it to the GPIO, and sends it back to the PC.
*   **`Makefile` & `sections.ld`**: Scripts that instruct the RISC-V GCC compiler on how to compile `main.c` and `start.S` into machine code (`firmware.elf`), convert it to binary (`firmware.bin`), and finally to a hex file (`firmware.hex`).
*   **`send_image.py`**: A Python script that runs on your laptop. It generates an image, sends it to the FPGA over the physical UART/USB cable, and prints the classification result it receives back.

---

## 2. Physical Setup: What You Need to Connect

To run this system physically, you will need:
1.  **FPGA Board**: (e.g., Altera/Intel DE2-115, as hinted in the python script).
2.  **USB Blaster Cable**: To program the FPGA with the hardware bitstream (RTL) from Quartus.
3.  **UART/Serial Cable**: For communication between the Python script and the PicoRV32. Depending on your board, this might be a standard RS-232 serial cable (requiring a USB-to-Serial adapter on modern laptops) or a built-in USB-UART bridge (like CP2102/FTDI).

**Physical Connections:**
1. Plug the FPGA into power.
2. Connect the USB Blaster port on the FPGA to your laptop.
3. Connect the UART/Serial port on the FPGA to your laptop.
4. Note down the **COM Port number** that appears in your laptop's Device Manager (e.g., `COM3`) when the UART cable is plugged in.

---

## 3. How the C Code is Uploaded

The C code is not uploaded in the traditional way (like an Arduino). Because the PicoRV32 is a "soft-core" inside the FPGA, the C code must be compiled and then baked into the FPGA's memory during the synthesis phase in Quartus.

1.  **Compile the Code**: You run `make` in the `sw/` directory. This produces `firmware.hex`.
2.  **Link to Hardware**: The `firmware.hex` file contains the raw machine instructions. The FPGA RAM module (inside the Quartus project) uses a Verilog system task like `$readmemh("firmware.hex", memory_array);` to initialize its memory contents. 
3.  **Synthesize**: When you compile your Quartus project, it reads `firmware.hex` and physically configures the FPGA's internal Block RAM to contain your compiled C program on boot.

*(Note: Advanced setups might use a bootloader to send C code over UART and load it into RAM dynamically, but based on your `Makefile`, the `.hex` file approach is being used).*

---

## 4. The Complete Step-by-Step Workflow

To get the entire system working from scratch, follow these steps:

### Step A: Compile the Software
1. Open a terminal (Linux/WSL/Git Bash) and navigate to `c:\intelFPGA_lite\DSD\Group_project\cnn_accelerator\sw\`.
2. You must have the **RISC-V GNU Toolchain** (`riscv32-unknown-elf-gcc`) installed.
3. Run the command: `make`
4. Verify that `firmware.hex` is successfully generated.

### Step B: Compile the Hardware (Quartus)
1. Open Intel Quartus Prime and open your project file (or create a new one pointing to the `rtl/` folder).
2. Ensure that your RAM initialization in `soc_top.sv` (or the respective memory module) is correctly pointing to the generated `firmware.hex` file.
3. Assign the correct FPGA pins for `clk`, `resetn`, `uart_rx`, `uart_tx`, and `gpio_out` (to LEDs/7-segment displays) using the Quartus Pin Planner.
4. Click **Compile Design** (this takes time as it synthesizes the Verilog into a bitstream).

### Step C: Program the FPGA
1. Open the Quartus Programmer.
2. Ensure your USB-Blaster is selected in Hardware Setup.
3. Add the generated `.sof` (SRAM Object File) and click **Start** to flash the FPGA.
4. The PicoRV32 CPU is now running your C code! (It is currently stuck in a `while(1)` loop waiting for the 'S' character over UART).

### Step D: Integrate Hardware/Software Interfaces (Teammate Task)
*Look at `sw/main.c`, lines 64-71.*
Currently, the C code receives the image but relies on a dummy calculation. The teammate responsible for the accelerator needs to:
1. Implement the memory mapping for the actual `cnn_acc.sv` inside `soc_top.sv` (currently just stubbed).
2. Uncomment the C code that writes `1` to `MAC_CTRL_BASE` to start the accelerator.
3. Read the actual result from `OUT_BRAM_BASE`.

### Step E: Run the Python Host Script
1. On your laptop, open `sw/send_image.py`.
2. Edit line 7: `COM_PORT = 'COM3'` to match the exact COM port of your USB-Serial cable (check Device Manager).
3. Open a terminal and run: `python send_image.py`

### 5. What happens during runtime (The Workflow)
1.  **Python** connects to the COM port and sends the ASCII character `'S'`.
2.  **C Firmware (`main.c`)** receives `'S'` via `uart_getchar()`. It changes the GPIO LEDs to `0x11111111` to indicate it is receiving data.
3.  **Python** sends 784 bytes of image data.
4.  **C Firmware** reads 784 bytes one-by-one from the UART hardware register and saves them into the `IMG_BRAM` memory space at `0x20000000`.
5.  **C Firmware** changes LEDs to `0x22222222` to indicate processing. It signals the Hardware CNN Accelerator (once implemented) to start by writing to the `MAC_CTRL` register.
6.  **Hardware (`cnn_acc.sv`)** pipeline activates, pulls the image from BRAM, crunches the numbers (Feature -> ReLU -> Pool -> Flatten -> Norm -> Classify), and flags `done` when finished.
7.  **C Firmware** detects the done flag, reads the result from `OUT_BRAM`, outputs the winning digit to the `GPIO` (7-segment displays), and sends `'R'` followed by the result byte back over UART.
8.  **Python** receives `'R'`, reads the next byte, and prints `"SUCCESS! FPGA Classified Digit as: X"` on your laptop screen.
