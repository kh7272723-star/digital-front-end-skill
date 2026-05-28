# VCD Waveform Analysis Guide

## Purpose

Teach the agent to analyze Value Change Dump (VCD) waveform files for debug. VCD is a text format — the agent can read it with the Read tool or parse it with a script. This guide covers format, extraction, protocol reconstruction, and bug localization.

---

## VCD File Format

### Header (one-time definitions)

```
$timescale 1s $end          — time unit
$scope module tb $end       — scope hierarchy
$var wire 1 ! signal_name $end  — signal definition: type, width, ID, name
$upscope $end               — end scope
$enddefinitions $end        — end of header
```

**Key fields in `$var`:**
- `wire`/`reg` — signal type (irrelevant for analysis)
- `1`/`32`/`4` — bit width
- `!` / `"` / `#` — **signal ID** (single character or printable ASCII). This is the key used in value change lines.
- `signal_name` — human-readable name

### Value changes (time-ordered)

```
#0                       — timestamp (in timescale units)
b00000000000000000000000000000000 !  — 32-bit bus value for signal ID "!"
1C                       — 1-bit value "1" for signal ID "C" (clk_i)
xI                       — unknown value for signal ID "I"
#10000000000             — next timestamp
b00000000000000000000000000000001 !  — bus value changed
```

**Format rules:**
- Lines starting with `#` are timestamps
- `b<binary_value> <ID>` for multi-bit signals
- `<scalar_value><ID>` for 1-bit signals (0, 1, x, z)
- Values only appear when they change (sparse representation)
- Timestamps are monotonically increasing

---

## How to Read VCD with Agent Tools

### Step 1: Extract the signal map

Use Grep to find all `$var` lines and build a signal-name-to-ID mapping:

```
Grep: pattern="\$var" path="dump.vcd" output_mode="content"
```

This produces lines like:
```
$var wire 1 ! s_axis_tready_o $end
$var wire 32 4 m_axis_tdata_o_3 [31:0] $end
```

Parse: signal name = field 5+, ID = field 4.

### Step 2: Find signals of interest

Search for specific signal names:

```
Grep: pattern="WVALID|WLAST|WREADY|AWVALID|AWREADY" path="dump.vcd" output_mode="content"
```

Note the signal IDs from the `$var` lines.

### Step 3: Extract value changes for target signals

Use the VCD helper script:

```bash
python scripts/vcd_extract.py dump.vcd --signals WVALID,WLAST,WREADY --range 0:1000000
```

Or use Grep to find changes for a specific signal ID (e.g., `!` for s_axis_tready_o):

```
Grep: pattern="^[01xzb].*!$|^b.*!$" path="dump.vcd" output_mode="content"
```

### Step 4: Identify clock edges

Find the clock signal (usually `clk_i` with ID `C`):

```
Grep: pattern="^[01]C$" path="dump.vcd" output_mode="content"
```

Each `1C` line is a posedge. Timestamps between consecutive `1C` lines define clock cycles.

---

## Protocol Sequence Reconstruction

### AXI Write Channel (AW/W/B)

To reconstruct an AXI write burst from VCD:

1. **Extract signals:** AWVALID, AWREADY, WVALID, WREADY, WLAST, WDATA, BVALID, BREADY
2. **Find AW handshake:** timestamp where `AWVALID=1 && AWREADY=1` (both high on same clock edge)
3. **Find W beats:** timestamps where `WVALID=1 && WREADY=1`, count until `WLAST=1`
4. **Find B response:** timestamp where `BVALID=1 && BREADY=1`
5. **Verify ordering:** AW before first W beat, B after WLAST

**Example reconstruction:**
```
Cycle  AWVALID AWREADY WVALID WREADY WLAST BVALID BREADY  Event
  10     1       1       0      0      0     0      0      AW handshake (addr accepted)
  11     0       0       1      1      0     0      0      W beat 0
  12     0       0       1      1      0     0      0      W beat 1
  13     0       0       1      1      1     0      0      W last beat
  14     0       0       0      0      0     1      1      B response
```

### APB Transaction

1. **Extract signals:** PSEL, PENABLE, PWRITE, PADDR, PWDATA, PRDATA, PREADY, PSLVERR
2. **SETUP phase:** `PSEL=1, PENABLE=0` (address latched)
3. **ACCESS phase:** `PSEL=1, PENABLE=1` (data transfer)
4. **Completion:** `PREADY=1` in ACCESS phase

### Ready/Valid Handshake

1. **Extract signals:** valid, ready, data
2. **Handshake fires:** `valid=1 && ready=1` on clock edge
3. **Stall:** `valid=1 && ready=0` — data must not change
4. **Backpressure propagation:** check if upstream ready deasserts when downstream stalls

---

## First Divergent Cycle Location

When a test fails, find the first cycle where actual behavior diverges from expected:

### Method 1: Signal comparison (if expected values are known)

1. Extract the actual signal timeline from VCD
2. Compare against expected values cycle by cycle
3. The first mismatch is the divergent cycle

### Method 2: Protocol violation detection

Search for known violation patterns in the VCD:

| Pattern | Signals | Condition |
|---------|---------|-----------|
| VALID dropped mid-handshake | valid, ready | valid was 1, ready was 0, valid becomes 0 |
| Payload changed under stall | valid, ready, data | valid=1, ready=0, data changes |
| WVALID gap in burst | WVALID, WLAST | WVALID was 1, becomes 0, WLAST not yet 1 |
| Missing completion | BVALID | WLAST fired but BVALID never asserts |

### Method 3: Binary search on large VCD

For large VCD files (>100MB):
1. Check mid-point timestamp: is the signal value correct or wrong?
2. If correct, search later half; if wrong, search earlier half
3. Repeat until the transition point is found

---

## Using the VCD Helper Script

```bash
# Extract specific signals as a timeline table
python scripts/vcd_extract.py dump.vcd --signals WVALID,WLAST,WDATA --range 0:50000

# Find all transitions of a signal
python scripts/vcd_extract.py dump.vcd --transitions WVALID

# Reconstruct AXI write channel
python scripts/vcd_extract.py dump.vcd --protocol axi-write

# Find first cycle where valid drops without ready
python scripts/vcd_extract.py dump.vcd --find-violation valid-drop --signals valid,ready
```

---

## Limitations

- VCD files can be very large (GB for complex designs). Use targeted extraction, not full-file reads.
- VCD records every signal change. For a 100MHz clock with 1000 signals, 1 second of simulation = ~100M lines.
- Multi-bit bus values are recorded as full-width binary strings, making manual parsing tedious — use the helper script.
- VCD does not record hierarchical signal names inline — you must cross-reference with the `$var` header.
- Icarus Verilog VCD output uses `$timescale 1s` by default. Check the header for actual scale.

---

## Common Debug Scenarios

### Scenario 1: Test hangs (no output)

1. Find clock signal, verify it's toggling
2. Find reset signal, verify it deasserts
3. Find FSM state signal, check if it's stuck in one state
4. Find handshake signals, check for deadlock (both sides waiting)

### Scenario 2: Wrong data output

1. Trace data path from input to output
2. Find the cycle where correct data enters the pipeline
3. Find the cycle where wrong data exits
4. Check intermediate registers at each pipeline stage

### Scenario 3: Protocol violation

1. Extract protocol signals (valid/ready/data/last)
2. Reconstruct the handshake sequence
3. Compare against protocol spec (AXI IHI0022E, APB IHI0024)
4. Flag the first violating cycle

### Scenario 4: Intermittent failure (passes sometimes)

1. Run simulation multiple times with different random seeds
2. Extract VCD from both passing and failing runs
3. Compare signal timelines to find the first divergence
4. Focus on signals driven by random stimulus or asynchronous events
