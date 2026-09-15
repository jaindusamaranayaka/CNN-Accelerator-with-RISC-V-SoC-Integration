# CNN Accelerator System: Overall Project Description

This document provides a comprehensive top-to-bottom overview of the CNN Accelerator project on FPGA. It explains how the hardware and software components interconnect, how the C program operates, how images are transmitted from a laptop, and how the hardware CNN pipeline activates and processes data.

---

## 1. System Architecture and Module Interconnection

The project is structured as a **System-on-Chip (SoC)** implemented on an FPGA. 

At the top level is `soc_top.sv`, which acts as the motherboard tying all sub-components together:
1.  **PicoRV32 CPU (`picorv32.v`)**: A 32-bit RISC-V soft-core processor. It is the main controller of the system.
2.  **Memory Map / Interconnect**: The CPU communicates with the rest of the system by reading and writing to specific 32-bit memory addresses:
    *   `0x10000000`: UART peripheral (Serial comms to laptop)
    *   `0x20000000`: Image BRAM (Where the input image is stored)
    *   `0x30000000`: Output BRAM (Where the CNN results are stored)
    *   `0x40000000`: MAC Control Register (Hardware trigger)
    *   `0x50000000`: GPIO (Output to board LEDs/7-Segment displays)
3.  **Hardware CNN Accelerator (`cnn_acc.sv`)**: The custom Verilog module that actually performs the high-speed math.

---

## 2. Image Transmission: PC to FPGA

The image transmission happens over a physical **USB cable** that acts logically as a UART (serial) connection.

1.  **Python Script (`send_image.py`)**: Running on your laptop, this script connects to the COM port assigned to the USB cable. It initiates the transfer by sending a start token (the ASCII character `'S'`).
2.  **Sending the Image**: Once the FPGA is ready, the Python script sends the 784 bytes (a 28x28 grayscale image) sequentially over the USB/UART connection.

---

## 3. The C Program (Firmware Workflow)

The C code (`main.c`) runs on the PicoRV32 processor inside the FPGA. Its job is to manage the flow of data.

1.  **Wait for Start**: It loops continuously, polling the UART status register, waiting to receive the `'S'` character.
2.  **Receive and Store**: Once `'S'` is received, it lights up the FPGA LEDs (writing `0x11111111` to GPIO) to indicate it's receiving. It then reads 784 bytes from the UART data register, one by one, and writes them directly into the Image Block RAM (BRAM) at base address `0x20000000`.
3.  **Activate Accelerator**: Currently, the C code does a dummy software calculation for testing. Once fully integrated, it will trigger the hardware CNN by writing a `1` to the MAC Control Register (`0x40000000`). It will then enter a `while` loop, waiting for a "done" flag from the hardware.
4.  **Return Result**: Once the hardware is done, the C code reads the classification result, outputs it to the physical 7-segment displays via GPIO, and sends an `'R'` character followed by the result byte back to the laptop over UART.

---

## 4. Hardware CNN Acceleration (`cnn_acc.sv`)

The true power of this project lies in `cnn_acc.sv`. When the C program sets the start signal, the hardware takes over, pulling the image data directly from memory.

### The 6-Stage Pipeline

The accelerator is designed as a **Hardware Pipeline**, meaning as one layer finishes processing a chunk of data, it passes it to the next layer while immediately starting on the next chunk. 

The modules interconnect sequentially using data buses (`_data`) and valid signals (`_valid`). A valid signal going high tells the next module that the data on the bus is ready to be consumed.

1.  **Feature Extraction (`feature1`)**: 
    *   Applies a convolution kernel (e.g., a 3x3 filter) over the input image buffer to extract edge and feature maps.
    *   Outputs `feature_data` and sets `feature_valid` high.
2.  **ReLU (`Relu`)**: 
    *   Takes the `feature_data`. Applies the Rectified Linear Unit activation function (replacing negative values with zero) to introduce non-linearity.
    *   Outputs `relu_data` and sets `relu_valid` high.
3.  **Pooling (`Pooling`)**: 
    *   Takes `relu_data`. Downsamples the feature map (usually via Max Pooling), reducing the spatial dimensions and computational load while keeping the most prominent features.
    *   Outputs `pool_data` and sets `pool_valid` high.
4.  **Flatten (`flatten`)**: 
    *   Takes the 2D `pool_data` arrays and flattens them into a single 1D continuous array, preparing it for the dense classification layers.
    *   Outputs `flatten_data` and sets `flatten_valid` high.
5.  **Normalize (`Normalize`)**: 
    *   Scales the flattened data to ensure numerical stability and improve classification accuracy.
    *   Outputs `normalize_data` and sets `normalize_valid` high.
6.  **Classification (`Classification`)**: 
    *   The final dense/fully-connected layer. It calculates the final probabilities for each digit (0-9).
    *   Outputs the winning digit on `class_result` and sets `classify_valid` high.

### Pipeline Synchronization

Between every stage in `cnn_acc.sv`, there is a clocked pipeline register (e.g., `feature_valid_r`). At the rising edge of every clock cycle, the valid signals propagate forward:
`Stage 1 (Feature) -> Stage 2 (ReLU) -> Stage 3 (Pool) ...`

When the final `classify_valid` signal goes high, it is assigned to the top-level `done` output. The PicoRV32 C program sees this `done` signal, reads the final `class_result`, and the hardware acceleration cycle is complete.

---

## 5. Current Progress & Next Steps

### What we have implemented so far:
*   **The Processor & SoC Framework**: The PicoRV32 soft-core processor is successfully integrated (`soc_top.sv`), along with basic memory routing for UART and GPIO.
*   **PC to FPGA Communication**: The Python script (`send_image.py`) successfully talks to the FPGA over the USB/COM port.
*   **C Firmware Framework (`main.c`)**: The C code can successfully listen for the start token (`'S'`), read a 784-byte image from UART, store it into the FPGA's memory (BRAM), and toggle LEDs. It also has a dummy classification algorithm running to prove the full loop works.
*   **CNN Hardware Skeleton**: `cnn_acc.sv` is structured with a clean 6-stage hardware pipeline architecture using valid signal synchronization.

### What we need to build next:
1.  **Hardware CNN Modules**: The internal logic for the 6 stages in `cnn_acc.sv` (Feature Extraction, ReLU, Pooling, Flatten, Normalize, Classification) needs to be fully written and tested.
2.  **Memory Map Integration**: In `soc_top.sv`, the `cnn_acc` module is currently sitting separately. It needs to be wired into the PicoRV32's memory bus so the C program can actually write to its image buffer and read its results.
3.  **Update C Firmware**: Uncomment and complete the lines in `main.c` to trigger the real hardware MAC register (`MAC_CTRL_BASE`) and read from the real Output BRAM (`OUT_BRAM_BASE`) instead of using the dummy `sum % 10` logic.
4.  **Simulation & Verification**: Run testbenches to verify that the hardware mathematically matches what a software CNN model would output.
5.  **Final Board Testing**: Program the physical FPGA board, send a real digit from the laptop, and verify the correct digit appears on the 7-segment display!
