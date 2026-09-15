"""
send_image.py — Host-side script for the CNN Accelerator RISC-V SoC

Protocol (per image):
  1. Host sends 'S'  (start token)
  2. Host sends 9 signed bytes  (3x3 kernel weights, row-major)
  3. Host sends 2 bytes  (bias, little-endian signed int16)
  4. Host sends 1 byte   (shift_s, 0-31)
  5. Host sends 784 bytes (28x28 grayscale image, row-major, unsigned)
  6. FPGA sends back 676 pairs: 'R' + 1 result byte
     (one per valid 3x3 window, row-major over the 26x26 output map)
"""

import serial
import time
import sys
import struct

COM_PORT  = 'COM3'
BAUD_RATE = 115200

IMAGE_W   = 28
IMAGE_H   = 28
NUM_WINDOWS = (IMAGE_W - 2) * (IMAGE_H - 2)   # 676


def send_image(image_bytes, kernel, bias, shift_s, port=COM_PORT):
    assert len(image_bytes) == IMAGE_W * IMAGE_H, "Image must be 784 bytes"
    assert len(kernel) == 9,                      "Kernel must be 9 values"
    assert -128 <= bias <= 127 or -32768 <= bias <= 32767, "Bias out of range"
    assert 0 <= shift_s <= 31,                    "shift_s must be 0-31"

    print(f"Connecting to FPGA on {port} at {BAUD_RATE} baud...")
    try:
        ser = serial.Serial(port, BAUD_RATE, timeout=5)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

    time.sleep(0.5)

    print("Sending start token...")
    ser.write(b'S')

    print("Sending kernel weights (9 bytes)...")
    ser.write(bytes([w & 0xFF for w in kernel]))

    print("Sending bias (2 bytes, little-endian)...")
    ser.write(struct.pack('<h', bias))

    print("Sending shift_s (1 byte)...")
    ser.write(bytes([shift_s & 0x1F]))

    print(f"Sending {IMAGE_W}x{IMAGE_H} image ({len(image_bytes)} bytes)...")
    ser.write(image_bytes)

    print(f"Waiting for {NUM_WINDOWS} convolution results...")
    results = []
    while len(results) < NUM_WINDOWS:
        token = ser.read(1)
        if token == b'R':
            val = ser.read(1)
            if val:
                results.append(int.from_bytes(val, byteorder='little', signed=True))

    ser.close()
    print(f"Received {len(results)} results.")
    return results


def make_dummy_image():
    return bytes([128] * (IMAGE_W * IMAGE_H))


def make_edge_kernel():
    kernel = [-1, -1, -1,
              -1,  8, -1,
              -1, -1, -1]
    bias     = 0
    shift_s  = 0
    return kernel, bias, shift_s


if __name__ == "__main__":
    image_bytes        = make_dummy_image()
    kernel, bias, shift_s = make_edge_kernel()

    print(f"Kernel: {kernel}  bias={bias}  shift_s={shift_s}")
    results = send_image(image_bytes, kernel, bias, shift_s)

    print("\nConvolution output map (26x26):")
    out_w = IMAGE_W - 2
    for row in range(IMAGE_H - 2):
        row_vals = results[row * out_w : row * out_w + out_w]
        print(" ".join(f"{v:4d}" for v in row_vals))
