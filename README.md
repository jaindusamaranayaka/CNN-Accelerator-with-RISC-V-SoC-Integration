# Member 2 — Dataflow & Memory

Line buffers, 3×3 sliding window, and edge padding for the FPGA CNN
accelerator. This module sits between the incoming AXI-Stream pixel feed
(driven upstream by Member 3's control FSM) and Member 1's MAC array, and
is responsible for turning a flat, raster-scan pixel stream into a
continuous stream of 3×3 spatial windows.

## Files

- `lineBufferAXI.sv` — single-row delay line (shift register).
- `slidingWindowAXI.sv` — line buffers + 3×3 register array + validity/padding logic.
- `tb_slidingWindowAXI.sv` — self-checking testbench with an independent golden model.

## `lineBufferAXI`

Parameters: `DATA_WIDTH` (bits/pixel), `ROW_LENGTH` (image width in pixels).

One pixel in per cycle (`wr_en`-gated), and `data_out` reflects whatever
pixel entered exactly `ROW_LENGTH` cycles earlier — i.e. "the pixel one
full image row ago."

**Current implementation is a full shift register** (`ROW_LENGTH` deep,
every element shifts every cycle). Correct and fine for small test images,
but this is **not yet BRAM-inferable** — Quartus will map it to registers,
not Block RAM. Rework into a single-port circular buffer (one
read/write pointer, wrapping at `ROW_LENGTH`) is still open — see Roadmap.

## `slidingWindowAXI`

AXI-Stream slave in (`s_axis_tdata/tvalid/tready`), AXI-Stream master out
(`m_axis_tdata` — a `[3][3]` array — `m_axis_tvalid/tready`).

### Pipeline

Two chained `lineBufferAXI` instances (`buffer1`, `buffer2`) produce two
row-delayed copies of the stream. Three 3-deep shift-register rows
(`reg_row_1/2/3`) are fed from the live stream and the two delayed copies
respectively, so at any moment they jointly hold a genuine 3×3 spatial
neighborhood. A combinational block remaps these into `m_axis_tdata`
(`reg_row_3`→output row 0/top, `reg_row_2`→row 1/middle, `reg_row_1`→row
2/bottom, matching normal top-to-bottom image reading order).

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
neighborhood. That happens once `pixel_count >= ROW_LENGTH + 2`.
`m_axis_tvalid` is driven combinationally (`assign m_axis_tvalid =
window_valid`) so it stays exactly in sync with `m_axis_tdata`, with no
extra register delay between them. Once valid, it stays high for the rest
of the frame (no longer drops at row boundaries, since padding gives every
column a legitimate output).

### Padding

Approach: **internal masking**, not stream injection — no extra pixels are
sent by anything upstream; instead each of the 8 non-center window slots
is independently checked against the real image bounds and forced to `0`
if it would reference a pixel outside them.

The center pixel's true image position is computed as a single combined
index first (`center_index = pixel_count - (ROW_LENGTH+2)`), then split
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

- [x] Line buffer + 3×3 window (register-array version)
- [x] `window_valid` (row/column boundary correctness)
- [x] Padding — all four edges (left/top/right/bottom), internally masked, fully verified for one full frame
- [ ] BRAM-inferable circular line buffer (current version is a full shift register)
- [ ] Re-verify AXI-Stream master handoff to Member 1 once the above are settled
- [ ] Quartus synthesis check — confirm BRAM inference, resource usage, timing

## Open questions for the team

- **Multi-frame operation is untested and its contract is undefined.** This module's position-tracking counters (`pixel_count`, `live_row`, `center_row`) never wrap on their own — they only reset via `rstn`. Streaming pixels continuously past one full frame with no `rstn` pulse in between produces incorrect behavior (row-position math computes nonsensical values once past the frame boundary). **Current assumption: one image is tested per reset — `rstn` must be pulsed between frames.** Whether that's actually how Member 3's control FSM will drive this module (a reset pulse per frame vs. some other frame-boundary signal) hasn't been confirmed — needs a conversation with Member 3 before multi-frame operation can be trusted.

## Known issues found & fixed during development

- Off-by-one in the original startup-latency counter's comparison timing (documented in-code, not a functional bug — verified against the diagram spec).
- Dead code branch in the original `m_axis_tvalid` logic (no-op, removed).
- Testbench race conditions: driver-vs-DUT stimulus race (fixed by moving stimulus updates to `negedge`), checker-vs-DUT same-posedge race (fixed by sampling on `negedge`).
- Padding mask computed via independent `live_row`/`live_col` subtraction incorrectly leaked wrong-row data across row boundaries (e.g. a window centered at the last column of a row could show a real-but-unrelated pixel instead of padding zero) — fixed by computing a single combined center index first, then deriving row/col via true division.
- `pixel_count` (formerly a saturating `valid_counter`) froze after reaching its old startup threshold, permanently freezing the padding mask's position — fixed by making it a genuinely free-running counter.
- `m_axis_tvalid` was briefly double-registered (one cycle behind `m_axis_tdata`), silently dropping the first valid window — fixed by driving it combinationally instead.