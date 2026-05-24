# AHB-Lite guidelines

## Purpose

Use this file for AHB-Lite slaves, simple bus bridges, and memory-mapped adapters.
This guidance is distilled from the Arm AMBA AHB protocol specification. Use `protocol-authority-map.md` when the exact AHB version matters.

## Conservative subset

Default to this subset until project rules are supplied:

- single manager AHB-Lite style interface,
- one clock domain,
- no split or retry behavior,
- one data phase response per accepted address phase,
- errors are explicit and do not silently update state.

## Phase discipline

AHB-Lite has separate address/control and data phases.
Generated RTL must not treat address acceptance and data availability as the same cycle event.

State the pipeline relation before RTL:

- address/control phase captures `haddr_i`, `hwrite_i`, `htrans_i`, `hsize_i`, and related controls when the previous transfer permits progress;
- data phase uses the registered controls from the previous accepted address phase;
- `hready_o` controls whether the current data phase completes and whether the next address phase can progress.

## Required contract points

- Which `htrans_i` values are treated as active transfers.
- How wait states are inserted with `hready_o`.
- How write data is aligned with the previous address phase.
- How read data and `hresp_o` are held during wait states.
- Which sizes, alignments, and protection attributes are supported.
- What happens on invalid address, unsupported size, or unaligned access.

## Required cycle rows

Include rows for:

- reset release,
- accepted address phase,
- following data phase,
- wait state in data phase,
- write data alignment,
- read data response,
- error response.

## Read data timing

AHB-Lite read data must be valid when `hready_o=1` in the data phase cycle. Two patterns:

**Pattern 1: Combinational read (recommended for simple slaves)**
Read data is combinationally from the CURRENT `haddr_i`. Available in the same cycle as the address phase. Simple, zero-latency.

```verilog
// Read data: combinational from current address
always @(*) begin
    hrdata_o = 32'd0;
    if (addr_in_range) hrdata_o = reg_file[addr_idx];
    else if (is_ctrl)  hrdata_o = ctrl_q;
end
```

**Pattern 2: Registered read (for pipelined slaves)**
Read data registered from previous address phase. One cycle latency, requires hready=0 wait state.

**Rule:** If using Pattern 1, ensure `hrdata_o` does NOT depend on `addr_q` (registered address) — use `haddr_i` (current address) directly. If `hrdata_o` depends on `addr_q`, the data is one cycle late and the master reads stale data.

**Source:** ARM AMBA AHB Protocol Specification (IHI 0033) §3.4: "The read data bus is used to transfer read data from the slave to the master... The read data must be valid when HREADY is HIGH."

## Verification minimum

For an AHB-Lite slave or bridge, include checks for:

- address/control and data phase alignment,
- no write using current-cycle address by mistake,
- `hready_o=0` holds the data phase,
- read data stability during wait,
- unsupported transfer response,
- back-to-back transfers with different read/write directions.

## Golden fixture

Use `evals/trials/ahb_lite_regs_trial` as the executable local example.
The fixture is independently written from the Arm AHB phase rules, with simple register-slave structure informed by common AHB-Lite peripheral templates.

It checks:

- write data uses the previous accepted address phase,
- `hready_o=0` holds the data phase,
- read data stays stable during wait,
- invalid address and unsupported size report error without updating state.

Run:

```text
python scripts/rtl_check.py --case evals/trials/ahb_lite_regs_trial
```
