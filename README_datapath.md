# Datapath & Classifier — Member 1

Owner: Rakesh. This document covers the arithmetic compute path and the
classifier head: what each module does, how the pieces fit, the design
decisions behind them, and the contracts the rest of the SoC has to honour.

Part of **CNN Accelerator with RISC-V SoC Integration** — MNIST digit
classification on a DE2-115 (Cyclone IV E, EP4CE115F29C7) at 50 MHz, driven
by a PicoRV32 soft core.

---

## 1. The model

```
Conv2d(1 -> 1, 3x3, padding=0)  ->  ReLU  ->  MaxPool(2x2)  ->  Linear(169 -> 10)
```

1710 parameters total, trained in PyTorch (`cnn_fpga/train.py`).

Tensor sizes at each stage:

| stage          | shape         | count |
| -------------- | ------------- | ----- |
| input image    | 28 x 28       | 784   |
| sliding window | 3 x 3 windows | 676   |
| conv + ReLU    | 26 x 26       | 676   |
| MaxPool 2x2    | 13 x 13       | 169   |
| Dense          | 10 logits     | 10    |
| Argmax         | 1 digit       | 1     |

**Single kernel is a deliberate simplification.** Conv2d(1->1) means one
filter, so there is no multi-kernel or multi-channel accumulation anywhere in
the hardware. This is acknowledged in the team README and is a scope decision,
not an oversight.

**No softmax in hardware.** Softmax is monotonic, so it never changes which
logit is largest. Argmax over the raw logits gives the identical answer and
saves an exponential and a division.

---

## 2. Module hierarchy

```
accel_top
├── feature_extract                 <- reusable per conv layer
│   ├── sliding_window              (Member 2)
│   ├── datapath_top                (Member 1)
│   │   ├── mac_array_3x3  ->  9 x mac_unit
│   │   ├── pipelined_adder_tree
│   │   ├── quant_sat_unit
│   │   └── relu_activation
│   └── maxpool
├── classifier_top                  <- runs once per image
│   ├── dense_layer
│   ├── argmax
│   └── bus handshake + result register
└── csr_block                       (Member 3)
```

### Why the split is at MaxPool -> Dense

Three reasons, in order of weight:

1. **Dataflow shape.** Everything in `feature_extract` streams: one beat in,
   one beat out, state is at most a row. Everything in `classifier_top`
   accumulates: 169 beats in, one answer out. Grouping by that property keeps
   each wrapper's control style uniform.
2. **Multi-layer reuse.** If the model ever gains a second conv layer,
   `feature_extract` is instantiated twice and chained. MaxPool is part of
   that repeating unit — every conv layer is followed by one. The classifier
   head stays singular at the end of the chain regardless of depth. Putting
   MaxPool in the classifier would break that.
3. **It is where the data changes meaning.** 13x13 spatial becomes a flat
   169-vector. That is the architectural boundary in the network itself.

### Multi-layer plan (not built)

If the design goes multi-layer, the leaning is **spatially chained** — one
`feature_extract` per layer streaming directly into the next, rather than
time-multiplexing one block through memory. Intermediate feature maps then
never touch memory at all, which is the memory-reduction argument.

Three things would need to become parameters: image width (drives both the
sliding window and MaxPool's `line_buf` depth), a ReLU bypass bit, and a
per-layer shift value (already a port).

One structural hook: real multi-channel networks must sum partial sums from
several input channels **before** requantizing. That accumulator would sit
between `pipelined_adder_tree` and `quant_sat_unit`. Those two stages are
deliberately not fused, so there is a clean place to insert it.

---

## 3. Modules

### 3.1 datapath_top — conv, quantize, activate

Status: **built, verified, timing-analysed.**

| submodule                | function                                | latency  |
| ------------------------ | --------------------------------------- | -------- |
| `mac_array_3x3`        | 9 parallel signed INT8 MAC lanes        | 2 cycles |
| `pipelined_adder_tree` | 3-level binary reduction + bias         | 3 cycles |
| `quant_sat_unit`       | arithmetic right shift + 3-way saturate | 1 cycle  |
| `relu_activation`      | sign-bit mux                            | 1 cycle  |

Total 7 cycles. End-to-end testbenches passing.

**Decisions:**

- **Non-systolic parallel MAC array.** Systolic was ruled out because at 3x3
  scale there is no operand reuse to exploit — a systolic array's advantage is
  sharing operands across many PEs, and with 9 lanes and a single filter there
  is nothing to share.
- **Binary adder tree, not carry-save.** CSA deferred to the optimization
  phase. The measured critical path is elsewhere (see below), so CSA would buy
  nothing today.
- **`relu_activation` kept as its own module** rather than folded into the
  quantization stage. Separable concerns, and it means a ReLU bypass for
  multi-layer use is a wrapper change rather than surgery inside the quantizer.
- **`shift_s[4:0]` is a runtime CSR port**, not a parameter. The quantization
  shift depends on the trained weights, so baking it into the bitstream would
  mean a full recompile after every retrain.
- **Pixels are unsigned, weights are signed.** Pixels are 0-255 and are
  zero-extended to a 9-bit always-positive signed value before multiplying
  with the signed int8 weight. The product still fits 16 bits.

**Timing:** SDC constrains `clk` to 20 ns (`create_clock -period 20 [get_ports CLOCK_50]`). Achieved Fmax 152.88 MHz, ~13.5 ns positive slack.

The measured critical path runs `pipelined_adder_tree|sum[...]` ->
`quant_sat_unit|data_out[...]` — the runtime-variable shift plus 3-way
saturate compare, **not** the adder tree or the DSP-to-fabric register hop as
originally suspected. An adder-tree rebalancing was designed and validated as
sound but is not the current priority, since it does not touch the real
bottleneck.

### 3.2 maxpool — 2x2 max pooling

Status: **written, not yet verified.**

Consumes a 26x26 feature map in raster order, emits 13x13.

**Structure — horizontal-first reduce.** Even columns are held in `h_reg`;
odd columns produce `h_max = max(h_reg, in_data)`. On even rows `h_max` is
stored in `line_buf`; on odd rows it is combined with the stored value and
emitted.

The structural property that licenses this: **max is associative and
commutative**, so reducing a 2x2 window horizontally-then-vertically gives the
same answer as any other order. (This does *not* transfer to a saturating sum,
which is why the adder tree cannot be reorganised as freely.)

The payoff: `line_buf` holds 13 entries, not 26, because each row is reduced
before being stored.

**Decisions:**

- **`line_buf` is 13 x 8-bit registers with combinational read, not BRAM.**
  104 bits total — an M9K would be wildly underused and its 1-cycle read
  latency would need matching on the other path.
- **No read-during-write hazard.** `line_buf` is written only on even rows and
  read only on odd rows, so a read and a write never land in the same cycle. A
  single-port register file is sufficient. The write enable is explicitly
  gated on row parity rather than writing unconditionally, so the module does
  not depend on read-before-write semantics — if `line_buf` ever becomes BRAM,
  nothing silently changes.
- **Explicit `sof` input**, rather than free-running self-synchronizing
  counters. The free-running design is correct only while the valid-pulse
  count per image is exactly 676 forever; if one is ever dropped, it
  misaligns silently and never recovers. `sof` converts that into a
  self-correcting failure.
- **Frame size fixed at 26x26.** No width parameter, since only that size is
  ever fed.

**Timing contract:** `sof` is high on the **same beat** as pixel (0,0),
matching AXI-Stream `tuser` semantics, and is ignored when `in_valid` is low.
Internally `r_eff`/`c_eff` override the registered counters on that beat so
the first pixel is both counted and processed in one cycle.

**Output is bursty.** 13 outputs per odd row spread over 26 input beats, then
26 beats of silence during the next even row. Downstream logic must advance on
`out_valid`, never on a cycle count. Latency is 1 cycle from the odd-column
input beat.

### 3.3 dense_layer — Linear(169 -> 10)

Status: **written, not yet verified.**

For each output neuron j:

```
logit[j] = bias[j] + sum over i of ( x[i] * w[j][i] )
```

**Structure — 10 parallel accumulator lanes**, one per digit, each with its
own weight memory. A pooled value arrives and all ten lanes consume it in the
same cycle against their own weight. 169 beats, then done.

Rejected alternative: a single shared MAC with a 1690-cycle FSM. Ten
multipliers cost ~10 of the device's 266 DSP blocks — not worth 169x the
latency to save.

**Pipeline — 3 stages:**

| cycle | action                                                                         |
| ----- | ------------------------------------------------------------------------------ |
| 0     | present`i` as weight read address; `p_reg <= data_in`; start `v1`/`l1` |
| 1     | weight out of BRAM;`prod[j] <= p_reg * w_rdata[j]`                           |
| 2     | `acc[j] <= acc[j] + prod[j]`; `valid_out <= l2`                            |

**`p_reg` exists to pay for BRAM read latency.** The pooled value arrives on a
wire (0 registers); the weight comes out of synchronous memory (1 register).
Without `p_reg`, every pooled value would meet the *previous* value's weight —
a silent, plausible-looking wrong answer. The alignment survives stalls
because `p_reg` and `i` are both gated on `valid_in`, so during a gap the BRAM
re-reads the same address and both sides freeze together.

**Widths, derived not guessed:**

| signal       | width               | reasoning                                               |
| ------------ | ------------------- | ------------------------------------------------------- |
| pooled value | 8 unsigned (0..127) | post-ReLU, zero-extended to 9-bit signed                |
| weight       | 8 signed            | int8                                                    |
| `prod`     | 17 signed           | 9-bit x 8-bit signed is naturally 17                    |
| `acc`      | 24 signed           | worst case -2,780,032 .. 2,758,569; 24-bit holds +-8.4M |
| bias         | 16 signed           | int16                                                   |

24 bits rather than a reflexive 32 saves 80 flip-flops across the ten lanes.

**Decisions:**

- **Biases preloaded into accumulators on `sof`**, not added at the end. The
  accumulator then does exactly one operation its whole life (`acc += prod`) —
  no special case on the last beat, no three-input adder on the worst cycle.
- **Weights live inside this module**, in 10 separate per-lane BRAMs
  (169 x 8-bit each). Ten lanes need ten different weights in the same cycle
  and one memory cannot serve ten reads, so they must be split per lane — and
  once split per lane, they belong with the lane.
- **`sof` is routed here too**, the same pulse MaxPool gets. It arrives ~700
  cycles before the first pooled value, which is harmless: it loads biases and
  zeros `i`, then waits. This is why MaxPool needs no `out_sof` port.
- **Output is a packed 240-bit bus**, not an unpacked array. Unpacked array
  ports are legal but awkward across tool and language-version boundaries.

**BRAM inference is template-matched, not described.** The per-lane memory is
written inside a `generate` loop with a specific shape: registered read, write
in the same clocked block, **no reset on the array, no initialization loop**.
An M9K is hard silicon with no reset wire on its storage, so adding a reset
forces Quartus to build the memory from flip-flops instead — ~13,500 registers
plus ten 169-to-1 muxes. This simulates identically, so it only shows up in
the fitter report.

**After compiling, confirm 10 M9K blocks and 10 DSP multipliers.** Zero M9K
with a spike in logic elements means the template broke.

### 3.4 argmax — pick the winning digit

Status: **written, under review.**

**Sequential scan: one comparator, one index counter, 10 cycles.**

A combinational scan over ten values chains nine 24-bit comparators in series
(~25 ns on a Cyclone IV -7) and misses the 20 ns budget. The scan uses one
comparator (~3 ns) and spends 10 cycles instead — free, after the 676 cycles
already spent on convolution.

General rule applied here: **parallel for things that run often, sequential
for things that run once.** `mac_array_3x3` is correctly 9 parallel
multipliers; argmax is correctly 1 comparator.

**Does not capture the logits.** `dense_layer`'s accumulators hold their final
value until the next `sof`, hundreds of cycles away, so the input bus is
stable for the whole scan and is read in place.

**Ties break toward the lowest index**, matching PyTorch `argmax`. This comes
free from using strict `>` rather than `>=`.

**The one corner case:** on the last cycle, lane 9's comparison result is not
yet in `best_id`, so the final assignment is
`class_id <= beats_best ? cnt : best_id`. Without that mux, lane 9 winning
would silently return the wrong digit. **Test a vector where lane 9 holds the
maximum.**

### 3.5 classifier_top — the head

Status: **written, not yet verified.**

Holds `dense_layer`, `argmax`, the bus handshake and the result register.

`dense_layer`'s logits are final on the **same** cycle its `valid_out` is
high, because both are registered on the same edge. So `argmax` samples on
that cycle and no pipeline register sits between them.

**Bus handshake** follows `uart_peripheral` exactly: `bus_ready` is registered,
defaults low, and goes high for one cycle when `bus_valid && !bus_ready`. The
`!bus_ready` term prevents a second acceptance while the master still holds
`bus_valid`. **If `bus_ready` is never driven the CPU hangs forever — the bus
has no timeout.**

`weight_wr_en` is combinational and true during that same acceptance cycle,
filtered to writes (`bus_wstrb != 0`). It must be true *during* the cycle
`bus_ready` is set, not after, because `dense_layer` samples it at that edge.

**Result register** is sticky so firmware can poll it: set on `argmax_valid`,
cleared by `sof`. `sof` has priority — a new image invalidates the previous
answer, and reporting "not ready" beats reporting a stale digit as fresh.

---

## 4. Address map

Full **byte** addresses, base attached. Confirmed by inspecting
`uart_peripheral`, whose registers sit 4 apart (`addr[3:0]` = 0x0 and 0x4) —
that spacing only occurs with byte addressing. Peripherals do **not** decode
the base; the interconnect has already done that.

| block | byte address     | contents                                    | decode                                        |
| ----- | ---------------- | ------------------------------------------- | --------------------------------------------- |
| 0..9  | `1024*n + 4*i` | dense weight, lane n, index i               | `lane = addr[13:10]`, `index = addr[9:2]` |
| 10    | `10240 + 4*j`  | dense bias j                                | `addr[15:10] == 10`                         |
| 11    | `11264`        | result, read-only:`{done, class_id[3:0]}` | `addr[15:10] == 11`                         |

Decode is pure bit-slicing because 1024 and 4 are powers of two. Padding each
lane to 1024 bytes (it only needs 676) spends unused address space — which is
free — to avoid a divider, which is not.

The 1024-byte spacing is in the **CPU's address space**, not in FPGA memory.
Only 169 words per lane are ever written and only 169 bytes per lane are
stored.

### Firmware contract (Member 3)

- **Load all weights and biases before streaming any pixels.** Port A and
  port B hit the same BRAM; a write landing mid-inference silently corrupts
  one lane for that image. The hardware does not and cannot cheaply prevent
  this.
- Poll block 11 bit 4 for done, then read bits 3:0 for the digit.
- Do not change weight order or register addresses without telling the team.

---

## 5. Data types

| item          | type          | notes                                         |
| ------------- | ------------- | --------------------------------------------- |
| pixels        | uint8, 0..255 | zero-extended to 9-bit signed before multiply |
| conv weights  | int8 x 9      | row-major, top-left first                     |
| conv bias     | int16         | consistent with`PROD_WIDTH`                 |
| dense weights | int8 x 1690   | 10 lanes x 169                                |
| dense biases  | int16 x 10    |                                               |
| pooled values | uint8, 0..127 | post-ReLU, so the MSB is always 0             |

Sliding window emits windows in normal reading order ([0][0] = top-left,
[2][2] = bottom-right), matching PyTorch `.flatten()`, no flip.

Dense input index `i` = `row * 13 + col`, row-major, which is exactly the
order MaxPool emits — so no reordering buffer is needed anywhere.

---

## 6. Open items

### Not built

- **`quantize.py` and the bit-exact integer reference model.** This is the
  critical path: every testbench needs its per-stage dumps, and Member 3 needs
  a firmware-ordered weight file plus test images with known answers.
- **Testbenches** for `maxpool`, `dense_layer`, `argmax`, `classifier_top`.
  Nine modules currently compile and none has been shown to compute a correct
  answer.
- **`feature_extract` wrapper** — ownership not yet settled.
- **AXI-Stream wrapper** on `datapath_top` — parked, see below.

### Deferred: the shared memory interface

The course brief asks for a domain accelerator sharing a **single memory**
with the CPU, minimizing memory transfer, evaluated primarily on *systems
performance*.

The current design has the CPU copying every byte through programmed I/O,
which is exactly the transfer the brief asks to eliminate. Options considered:

| option                           | memory traffic             | notes                                               |
| -------------------------------- | -------------------------- | --------------------------------------------------- |
| slave + programmed I/O (current) | data crosses the bus twice | CPU is a copy engine                                |
| slave + DMA engine               | once                       | generic block mover, no knowledge of access pattern |
| accelerator as bus master        | once, CPU free             | needs a multi-master arbiter from Member 3          |
| shared dual-port on-chip BRAM    | none                       | whole working set is ~2.5 KB — fits easily         |
| PCPI coprocessor                 | n/a                        | wrong shape; passes registers, not streams          |

**Dual-port BRAM is the honest fit at this scale.** Bus mastering is the
stronger scaling argument for the report. Spatial chaining already removes
most intermediate traffic on its own.

This is deferred, and the AXI-Stream wrapper stays parked behind it since it
sits on that boundary.

### AXI-Stream: why internal interfaces do not use it

`tready` — backpressure — is AXI-Stream's one substantive feature over plain
`valid`/`data`. No internal boundary in this design can stall: every module
accepts one beat per cycle indefinitely, and `dense_layer`'s logits stay
stable until the next frame. `tready` would be tied high everywhere.

Member 2's sliding window *does* speak AXI-Stream, correctly — it reads BRAM
and can stall. On this side `tready` is simply tied high.

---

## 7. Recurring bugs worth watching for

Collected from actual bugs caught in this project:

- Missing `signed` on a flattened bus slice causes silent zero-extension of
  negative values. SystemVerilog decides signed vs unsigned multiplication
  from the **operand declarations**, so a missing `signed` fifty lines away
  changes the arithmetic.
- Same-cycle stale reads: reading a signal in the same `always_ff` block where
  it was just assigned with `<=`.
- Valid signals must be delayed by exactly as many register stages as the data
  they accompany.
- Two signals meeting at a gate must have crossed the same number of registers
  since they last agreed. Pad the **shorter** path; never shorten the longer.
- Port width mismatches from reusing the wrong parameter.
- `20'sd(-5)` is illegal; the correct form is `-20'sd5`.
- A counter that advances on a bare clock edge rather than on `valid` will
  desync from the data on the first stall.
