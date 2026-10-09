# Member 3: SoC Integration & System Architecture

**Author:** Jaindu Samaranayaka (Member 3)  
**Role:** SoC Integration, PicoRV32 CPU Interfacing, Interconnect, Memory Buffers, Peripherals, Firmware & Verification.

---

## 1. Responsibilities & Architecture

Member 3 is responsible for the top-level System-on-Chip (SoC) integration that links the RISC-V soft processor to all memory blocks, peripherals, and the CNN acceleration pipeline.

### Top-Level Modules Managed
1. **`cnn_soc_top.sv`**:
   - Motherboard module instantiating PicoRV32 CPU, `soc_bus_interconnect`, RAM, UART, GPIO, and the unified `cnn_core` accelerator pipeline.
   - Decodes 7-segment display drivers from `gpio_out` bus.
2. **`soc_bus_interconnect.sv`**:
   - High-throughput address decoder and bus multiplexer routing PicoRV32 memory requests.
3. **`image_buffer_bram.sv`**:
   - Dual-port image buffer RAM enabling CPU writes from UART while the streaming read engine independently fetches pixel batches for the CNN datapath.
4. **`pixel_stream_reader.sv`**:
   - Translates 32-bit packed word entries in BRAM into an AXI-Stream 8-bit pixel stream with start-of-frame `m_axis_tuser` flagging and backpressure support.
5. **`uart_serial_controller.sv`**:
   - Memory-mapped serial receiver and transmitter with internal clock divider, bit synchronization, and status register flags.
6. **`display_gpio_peripheral.sv`**:
   - 32-bit memory-mapped I/O driving board status indicators and 7-segment displays.

---

## 2. Memory Map Specification

| Base Address | Device | Functions & Offsets |
| :--- | :--- | :--- |
| `0x0000_0000` | **RAM (64 KB)** | Firmware executable code and data stack |
| `0x1000_0000` | **UART** | `+0x0`: Data register (TX write, RX read with auto-ack)<br>`+0x4`: Status register (`bit 0` = tx_ready, `bit 1` = rx_valid) |
| `0x2000_0000` | **Image BRAM** | Dual-port buffer written by firmware, read by `pixel_stream_reader` |
| `0x3000_0000` | **Output BRAM** | Classification result latch; read clears the class ready flag |
| `0x4000_0000` | **MAC / Accel Control** | `+0x0`: Start trigger & status (`bit 0` = busy, `bit 1` = done)<br>`+0x4`: Image base address<br>`+0x8`: Image length in bytes<br>`+0xC..0x14`: Conv weights, bias, shift |
| `0x5000_0000` | **GPIO** | `+0x0`: 32-bit output vector driving HEX0–HEX7 displays |
| `0x6000_0000` | **Dense Weights** | Direct write port for neural network classifier weights |

---

## 3. Comprehensive Verification & Testing Suite

All modules were verified in `tb/soc_integration_jaindu/` under ModelSim Intel FPGA Edition across 5 verification categories:

### Test Dimensions
- **[F] Functional Testing**: Byte lane writes (`wstrb`), address decoding across all 7 ranges, UART loopback serial data integrity, and BRAM byte extraction order.
- **[I] Interface Testing**: Bus handshakes (`valid`/`ready`), register offset decoding (`0x0` data vs `0x4` status), and AXI-Stream `tuser` framing on the initial pixel.
- **[T] Timing Testing**: Single-cycle response latency, back-to-back bus cycles, BRAM 1-cycle synchronous read latency, and UART baud rate tick generation.
- **[P] Protocol Testing**: AXI-Stream backpressure resilience under arbitrary `m_axis_tready` wait states, auto-clearing of UART `rx_valid` flag upon reading data register, and mutual exclusivity of slave selects.
- **[C] Corner-Case Testing**: Asynchronous reset recovery mid-transaction, unmapped memory access handling (`0x7000_0000`), zero-strobe write attempts, and single-byte transfers (`img_len = 1`).

### Test Results (83 / 83 Tests Passed - 100% Pass Rate)

| Testbench | Module Under Test | Tests Executed | Passed | Failed | Pass Rate |
| :--- | :--- | :---: | :---: | :---: | :---: |
| [`tb_display_gpio_peripheral.sv`](../tb/soc_integration_jaindu/tb_display_gpio_peripheral.sv) | `display_gpio_peripheral.sv` | 16 | 16 | 0 | **100%** |
| [`tb_soc_bus_interconnect.sv`](../tb/soc_integration_jaindu/tb_soc_bus_interconnect.sv) | `soc_bus_interconnect.sv` | 24 | 24 | 0 | **100%** |
| [`tb_image_buffer_bram.sv`](../tb/soc_integration_jaindu/tb_image_buffer_bram.sv) | `image_buffer_bram.sv` | 11 | 11 | 0 | **100%** |
| [`tb_pixel_stream_reader.sv`](../tb/soc_integration_jaindu/tb_pixel_stream_reader.sv) | `pixel_stream_reader.sv` | 19 | 19 | 0 | **100%** |
| [`tb_uart_serial_controller.sv`](../tb/soc_integration_jaindu/tb_uart_serial_controller.sv) | `uart_serial_controller.sv` | 13 | 13 | 0 | **100%** |
| **Total** | | **83** | **83** | **0** | **100%** |

---

## 4. Hardware Bugs Found & Resolved

1. **Parameter Header Syntax in `image_buffer_bram.sv` & `uart_serial_controller.sv`**:
   - Both modules lacked `#(` in the parameter declaration, preventing compilation under SystemVerilog strict standards. Resolved.
2. **Sequential Multiplexing Issue in `pixel_stream_reader.sv`**:
   - `m_axis_tdata` was registered sequentially during state transitions, causing the 4th byte (`current_word[31:24]`) to be skipped when entering `READ_REQ`. 
   - Replaced with combinational multiplexing from `current_word` with clean `m_axis_tvalid` handshaking and `m_axis_tuser` marking.

---

## 5. How to Run Verification

### Turnkey ModelSim Execution
```powershell
cd tb\soc_integration_jaindu
vsim -c -do run_tests.do
```

### Individual Test Run
```powershell
vlog -sv rtl/soc_integration_jaindu/display_gpio_peripheral.sv tb/soc_integration_jaindu/tb_display_gpio_peripheral.sv
vsim -c -do "run -all; quit" tb_display_gpio_peripheral
```
