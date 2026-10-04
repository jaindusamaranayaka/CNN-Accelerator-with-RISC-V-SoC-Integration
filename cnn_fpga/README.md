# FPGA CNN Training & Weight Extraction

This directory contains the Python software reference model used to train and extract weights for the RISC-V SoC CNN Accelerator.

## Goal
The purpose of this folder is **not** to build a generic, highly-accurate CNN. Instead, the goal is to build a **Software Reference Model** in PyTorch that exactly mirrors the hardware architecture implemented in SystemVerilog. 

By matching the hardware exactly, we can train the model in Python, extract the weights, quantize them, and send them to the FPGA so the hardware outputs the exact same predictions as the software.

## Architecture 
The pipeline implemented here strictly matches the hardware pipeline:
1. **Conv2D** (3x3 kernel, 1 channel in, 1 channel out, bias) -> mirrors `datapath_top.sv`
2. **ReLU** -> mirrors `relu_activation.sv`
3. **MaxPool2d** (2x2 kernel, stride 2) -> mirrors `max_pool_2d.sv`
4. **Flatten** (13x13 = 169 values)
5. **Dense / Linear** (169 inputs -> 10 outputs) -> mirrors `dense_layer.sv`
6. **Argmax** (Highest score wins) -> mirrors `argmax.sv`

**Total Learnable Parameters:** 1,710
- Conv Kernel: 9 weights
- Conv Bias: 1 weight
- Dense Matrix: 1690 weights
- Dense Bias: 10 weights

## What We Have Done So Far

### 1. Training (`train.py`)
We built a PyTorch model (`FPGACNN`) representing the exact 1,710-parameter hardware architecture. We trained it on the MNIST handwritten digit dataset for 10 epochs.
- It takes a 28x28 grayscale image as input.
- Uses standard CrossEntropyLoss and the Adam optimizer.
- Outputs the trained model to `models/fpga_cnn.pth`.

### 2. Weight Extraction (`extract_weights.py`)
We wrote a script that loads the trained `.pth` model and pulls out the 1,710 floating-point (FP32) values.
- It flattens the 3x3 convolution kernel into row-major order.
- It extracts the 10x169 dense weight matrix.
- It saves everything as human-readable text files in the `weights/` directory.

### Directory Structure
```
cnn_fpga/
├── data/               # Auto-downloaded MNIST dataset
├── models/             # Contains fpga_cnn.pth (trained model) and training curves
├── weights/            # Contains the extracted FP32 weights (.txt)
├── train.py            # Training script
└── extract_weights.py  # Weight extraction script
```

## Next Step: Quantization (PENDING)
**WARNING:** Do not send the FP32 weights directly to the FPGA, and do not arbitrarily round them with `int()`. 

The FPGA expects integer (fixed-point) arithmetic. We must now inspect the SystemVerilog files (specifically `quant_sat_unit.sv` and `dense_layer.sv`) to determine the exact bit-widths and shifting mechanisms used in hardware. Once understood, we will create `quantize.py` to scale and convert the FP32 weights into the exact binary format expected by the FPGA.
