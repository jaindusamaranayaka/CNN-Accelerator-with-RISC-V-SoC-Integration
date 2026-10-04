# CNN Accelerator with RISC-V SoC Integration

An FPGA system-on-chip that classifies handwritten digits (MNIST, 28×28) using a
custom CNN accelerator controlled by a PicoRV32 RISC-V soft core.

**Target:** Terasic DE2-115 (Cyclone IV E, EP4CE115F29C7), 50 MHz

## Architecture

```
Laptop --UART--> PicoRV32 --bus--> Sliding window (3x3) --> Conv datapath --> Max pool --> Dense --> Argmax
                    ^                                                                                  |
                    +----------------------------- result register / status --------------------------+
```

1. The host sends the weights and a 28×28 image over UART.
2. Firmware loads the weights into memory-mapped registers and streams the pixels to the accelerator.
3. The accelerator runs **Conv 3×3 (valid) → ReLU → MaxPool 2×2 → Dense 169→10 → Argmax** entirely in hardware.
4. The firmware reads the predicted digit, shows it on the 7-segment display, and returns it over UART.

**Model:** `Conv2d(1→1, 3×3, padding=0)` → ReLU → MaxPool(2) → Linear(169→10), giving 1,710 parameters (`cnn_fpga/train.py`).

## Memory map

| Address | Device |
|---|---|
| `0x0000_0000` | RAM, 64 KB (firmware) |
| `0x1000_0000` | UART: `+0x0` data, `+0x4` status (bit 0 TX ready, bit 1 RX valid) |
| `0x2000_0000` | Pixel stream into the sliding window (write-only) |
| `0x3000_0000` | Classification result (read clears the ready flag) |
| `0x4000_0000` | Conv control: `+0x0` enable / status, `+0x4..0xC` weights, `+0x10` bias, `+0x14` shift |
| `0x5000_0000` | GPIO → 7-segment displays |
| `0x6000_0000` | Dense weights (`+1024·n + 4·i`) and biases (`+0x2800 + 4·n`) |

## Repository layout

```
rtl/            SoC top, interconnect, peripherals, sliding window, classifier
rtl/datapath/   MAC array, adder tree, quantize/saturate, ReLU
tb/             Testbenches
sw/             Firmware (start.S, main.c, linker script, Makefile) and host script
cnn_fpga/       Training and weight extraction (PyTorch)
```

## Team

| Member | Area |
|---|---|
| 1 | Datapath and arithmetic: MAC, adder tree, quantization, ReLU, pooling |
| 2 | Dataflow and memory: line buffers, 3×3 sliding window, padding ([details](rtl/README_member2.md)) |
| 3 | SoC integration: CPU, interconnect, peripherals, firmware, timing |

## Status

### Done
- **Sliding window** (`slidingWindowAXIBRAM`)
  - BRAM line buffers, confirmed to map to M9K in Quartus.
  - AXI-Stream handshake: one window per input pixel, safe under backpressure.
  - Valid and padded convolution modes (`PADDING` parameter).
  - Start-of-frame restart (`s_axis_tuser`).
  - Standard left-to-right window order.
  - Verified by directed and constrained-random stall testbenches in both modes.
- **Conv datapath:** 9 parallel MACs, pipelined adder tree, shift/saturate and ReLU (7-cycle latency).
- **Classifier:** max pool, dense layer with CPU-loadable weights, and argmax.
- **SoC:** PicoRV32, address decoder, UART, GPIO, and firmware for loading weights and streaming pixels.
- **Model:** training and FP32 weight extraction.

### To do

| Owner | Item |
|---|---|
| 3 | Fix the `firmware.hex` format: one 32-bit word per line, not one byte (currently the CPU cannot boot) |
| 3 | Fix the UART receiver bit count (`rx_bit_cnt` 9 → 10) |
| 3 | Instantiate `slidingWindowAXIBRAM` (`ROW_LENGTH=28`, `PADDING=0`) and connect `s_axis_tuser` |
| 3 | Make the pixel-stream `tvalid` a single-cycle pulse per store |
| 3 | Firmware: mark the first pixel of each image (start of frame), and send 2 drain pixels after the image |
| 3 | Add SDC constraints (50 MHz); run a full compile and timing analysis |
| 1 | Treat pixels as unsigned in `mac_unit` (unsigned pixel × signed weight) |
| 1 | Write `quantize.py` (int8 weights, bias and shift) with a bit-exact integer reference model |
| 2 | Size `pixel_count` to its real range; check the divider timing at 50 MHz |
| All | End-to-end SoC simulation with a real MNIST digit, compared against the integer reference model |
| All | Power analysis report |

## Build and run

**Train and export the model**
```
cd cnn_fpga
python train.py
python extract_weights.py
```

**Build the firmware** (needs `riscv32-unknown-elf-gcc`)
```
cd sw && make
```

**Run on the FPGA:** compile in Quartus with `soc_top` as the top level, program the board, then:
```
python sw/send_image.py
```

**Simulate the sliding window:** compile the files in `rtl/` and `tb/` (tested with Cadence Xcelium).

## Known limitations

- Square images only: the padding logic uses `ROW_LENGTH` as the image height.
- One convolution filter, so accuracy is limited compared with multi-filter CNNs.