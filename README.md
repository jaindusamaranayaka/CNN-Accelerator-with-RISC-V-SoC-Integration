# Member 2 — Dataflow & Memory

Line buffers, 3×3 sliding window, and edge padding for the FPGA CNN
accelerator. This module sits between the incoming AXI-Stream pixel feed
(driven upstream by Member 3's control FSM) and Member 1's MAC array, and
is responsible for turning a flat, raster-scan pixel stream into a
continuous stream of 3×3 spatial windows.

## Files

- `lineBufferAXIBRAM.sv` — single-row delay line, BRAM-inferable circular buffer (single read/write pointer). Confirmed via Quartus (Cyclone IV E) to actually map to M9K blocks.
- `slidingWindowAXIBRAM.sv` — line buffers + 3×3 register array + validity/padding logic.
- `tb_slidingWindowAXIBRAM.sv` — self-checking testbench with an independent golden model.

(Earlier shift-register-based versions, `lineBufferAXI.sv`/`slidingWindowAXI.sv`, are superseded by the BRAM versions above and kept only for reference.)

## `lineBufferAXIBRAM`

Parameters: `DATA_WIDTH` (bits/pixel), `ROW_LENGTH` (image width in pixels).

One pixel in per cycle (`wr_en`-gated), and `data_out` reflects whatever
pixel entered exactly `ROW_LENGTH` cycles earlier — i.e. "the pixel one
full image row ago" — plus one extra cycle of registered-read latency (see
below).

**Implementation:** a single memory array (`mem[0:ROW_LENGTH-1]`, tagged
`(* ramstyle = "M9K" *)`) with one pointer register that writes and reads
the *same* address each cycle, wrapping at `ROW_LENGTH`. Both the write and
the (registered) read live in one `always_ff`, matching Intel's recognized
single-port RAM inference template — confirmed via Quartus's RAM Summary
report to actually synthesize into M9K blocks (10,240 total memory bits for
two `ROW_LENGTH=640` buffers, 0 before the fix — see Known Issues Fixed).

**Important: the read is registered, not combinational** (`data_out <=
mem[ptr]`, inside `always_ff`) — this matches real M9K hardware, which
registers its read port. This adds exactly **+1 cycle of latency per
buffer** compared to the old shift-register version's combinational read.
Since the pipeline chains two of these, `reg_row_2`'s path picks up +1 cycle
and `reg_row_3`'s path picks up +2, relative to `reg_row_1` (which has no
buffer in its path at all) — see the compensating delays below.

## `slidingWindowAXIBRAM`

AXI-Stream slave in (`s_axis_tdata/tvalid/tready`), AXI-Stream master out
(`m_axis_tdata` — a `[3][3]` array — `m_axis_tvalid/tready`).

### Pipeline

Two chained `lineBufferAXIBRAM` instances (`buffer1`, `buffer2`) produce two
row-delayed copies of the stream. Three 3-deep shift-register rows
(`reg_row_1/2/3`) are fed from the live stream and the two delayed copies
respectively, so at any moment they jointly hold a genuine 3×3 spatial
neighborhood. A combinational block remaps these into `m_axis_tdata`
(`reg_row_3`→output row 0/top, `reg_row_2`→row 1/middle, `reg_row_1`→row
2/bottom, matching normal top-to-bottom image reading order).

**Delay compensation (BRAM-specific, not needed in the old shift-register
version):** because each BRAM buffer adds +1 cycle of registered-read
latency, and `reg_row_1`/`reg_row_2`/`reg_row_3` pass through 0/1/2 buffers
respectively, every row's source is padded with extra plain registers so
all three stay column-aligned:
- `reg_row_1[0]` fed from `s_axis_tdata` through **2** compensating registers (`s_axis_tdata_delay`, `s_axis_tdata_delay2`).
- `reg_row_2[0]` fed from `line_out_1` through **1** compensating register (`line_out_1_delay`).
- `reg_row_3[0]` fed directly from `line_out_2`, no compensation (it already carries the most real delay).

### Position tracking

- `pixel_count` — free-running count of completed transfers (never
  saturates; only resets via `rstn`).
- `live_col` / `live_row` — the real image `(row, col)` of the pixel
  currently arriving. `live_col` wraps every `ROW_LENGTH` pixels; `live_row`
  increments once per row and does **not** wrap (a new image only begins
  after reset).

### Validity (`window_valid` / `m_axis_tvalid`)

With padding in place, the module only needs the **center** slot
(`reg_row_2[1]`) to hold a real pixel — not a fully-surrounded 3×3
neighborhood. That happens once `pixel_count >= ROW_LENGTH + 4` (the `+4`,
up from `+2` in the pre-BRAM version, accounts for the two compensating
register stages now sitting ahead of the center). `m_axis_tvalid` is driven
combinationally (`assign m_axis_tvalid = window_valid`) so it stays exactly
in sync with `m_axis_tdata`, with no extra register delay between them.
Once valid, it stays high for the rest of the frame (no longer drops at row
boundaries, since padding gives every column a legitimate output).

### Padding

Approach: **internal masking**, not stream injection — no extra pixels are
sent by anything upstream; instead each of the 8 non-center window slots
is independently checked against the real image bounds and forced to `0`
if it would reference a pixel outside them.

The center pixel's true image position is computed as a single combined
index first (`center_index = pixel_count - (ROW_LENGTH+4)`), then split
into `center_row`/`center_col` via real division — **not** by subtracting
row and column independently, which breaks at row boundaries (doesn't
"borrow" correctly; this was a real bug found and fixed during
development — see Known Issues Fixed).

Four flags gate the 8 non-center slots based on the center's position:

```
right_ok  = (center_col <= ROW_LENGTH-2)   // real neighbor one column right
left_ok   = (center_col >= 1)              // real neighbor one column left
top_ok    = (center_row >= 1)              // real neighbor one row up
bottom_ok = (center_row <= ROW_LENGTH-2)   // real neighbor one row down
```

**Square-image assumption:** `bottom_ok` reuses `ROW_LENGTH` as the image height (no separate height parameter exists). This is a deliberate simplification, not a general solution — a non-square image would need its own height input and a corresponding change to `bottom_ok`.

## Testbench

Self-checking against an independent golden model — no logic is shared
with the DUT's own implementation, so a shared bug can't hide from both
sides:

- `predict(n, offset)` — looks up what pixel value *should* be at a given
  register slot, from a testbench-side history array (`sent_pixels[]`).
- `get_masks(n, ...)` — independently recomputes `right_ok`/`left_ok`/`top_ok`
  from `n` alone, mirroring the RTL's own derivation.
- Checks run every cycle: `m_axis_tvalid` against an independently-derived
  expected-validity signal, and all 9 `m_axis_tdata` positions (data value
  **and** correct zero-masking) against the combination of the two
  functions above.

Driver holds `tvalid`/`tready` high continuously (no backpressure stress
test yet) and streams enough sequential, distinguishable pixel values to
exercise several full row wraps. Zero mismatches confirms both the pixel
data and the padding/validity timing are correct — not just "looks right
on the waveform."

## Status

- [x] Line buffer + 3×3 window
- [x] `window_valid` (row/column boundary correctness)
- [x] Padding — all four edges (left/top/right/bottom), internally masked, fully verified for one full frame
- [x] BRAM-inferable circular line buffer — implemented, delay-compensated, and **confirmed via Quartus synthesis** (Cyclone IV E / DE2-115) to actually map to M9K blocks, not registers
- [ ] Backpressure/handshake testing (`m_axis_tready` dropping mid-stream) — not yet tested; all testing so far uses continuous flow, no stalls
- [ ] Re-verify AXI-Stream master handoff to Member 1
- [ ] Full Quartus compile (Fitter/Assembler) + timing closure — needs Member 3's SDC constraints first; Analysis & Synthesis alone (sufficient for confirming BRAM inference) has been done

## Open questions for the team

- **Multi-frame operation is untested and its contract is undefined.** This module's position-tracking counters (`pixel_count`, `live_row`, `center_row`) never wrap on their own — they only reset via `rstn`. Streaming pixels continuously past one full frame with no `rstn` pulse in between produces incorrect behavior (row-position math computes nonsensical values once past the frame boundary). **Current assumption: one image is tested per reset — `rstn` must be pulsed between frames.** Whether that's actually how Member 3's control FSM will drive this module (a reset pulse per frame vs. some other frame-boundary signal) hasn't been confirmed — needs a conversation with Member 3 before multi-frame operation can be trusted.

## Known issues found & fixed during development

- Off-by-one in the original startup-latency counter's comparison timing (documented in-code, not a functional bug — verified against the diagram spec).
- Dead code branch in the original `m_axis_tvalid` logic (no-op, removed).
- Testbench race conditions: driver-vs-DUT stimulus race (fixed by moving stimulus updates to `negedge`), checker-vs-DUT same-posedge race (fixed by sampling on `negedge`).
- Padding mask computed via independent `live_row`/`live_col` subtraction incorrectly leaked wrong-row data across row boundaries (e.g. a window centered at the last column of a row could show a real-but-unrelated pixel instead of padding zero) — fixed by computing a single combined center index first, then deriving row/col via true division.
- `pixel_count` (formerly a saturating `valid_counter`) froze after reaching its old startup threshold, permanently freezing the padding mask's position — fixed by making it a genuinely free-running counter.
- `m_axis_tvalid` was briefly double-registered (one cycle behind `m_axis_tdata`), silently dropping the first valid window — fixed by driving it combinationally instead.
- **BRAM's registered read silently broke column alignment.** Switching the line buffer to a real M9K-inferring design (registered read, per Intel's required template) added +1 cycle of latency per buffer that the shift-register version never had. Since `reg_row_1`/`2`/`3` pass through 0/1/2 buffers respectively, this desynchronized their column alignment — fixed with explicit compensating registers on `reg_row_1`'s and `reg_row_2`'s sources (2 and 1 extra register stages respectively) so all three rows stay aligned, plus updating `window_valid`'s threshold and `center_index` from `ROW_LENGTH+2` to `ROW_LENGTH+4` to match.
- **Resetting the BRAM array's contents silently prevents BRAM inference.** Intel/Quartus documentation confirms real Block RAM hardware cannot clear its contents via a reset signal — any HDL that resets a memory array's contents (as opposed to just an output register) gets synthesized as ordinary logic cells instead, with no error, just a "Total memory bits: 0" in the synthesis report. Fixed by removing the reset on `mem[]` in `lineBufferAXIBRAM` (keeping the reset on the separate `data_out` register, which is fine — it's not memory content). Confirmed safe: `window_valid` already guarantees nothing downstream trusts a buffer's output before every address has been written with real data at least once.