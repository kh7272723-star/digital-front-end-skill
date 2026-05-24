# DFT (Design for Testability) Guidelines

## Purpose

This file covers DFT concepts relevant to RTL engineers. Use when the task involves scan insertion, BIST, test access, or production test considerations.

## Why DFT matters

- Manufacturing defects cannot be caught by functional simulation alone
- DFT structures enable automated test pattern generation (ATPG)
- Without DFT, defect coverage is unpredictable and yield is unverifiable

## Scan chain basics

### Concept

Replace every flip-flop with a scan flip-flop that has a scan-in (SI) and scan-enable (SE) pin. In test mode, SE=1 and the chain shifts in/out test vectors.

### RTL implications

- Do not use latches as state elements (they break scan chains)
- Do not use asynchronous set/reset on flops unless absolutely necessary
- Keep combinational logic between flops scannable (no latches, no tri-state without enable)
- Avoid gated clocks in test mode (use test mode override)

### Rules for RTL engineers

```verilog
// GOOD: synchronous reset, scannable
always @(posedge clk) begin
  if (rst)
    q <= 1'b0;
  else
    q <= d;
end

// BAD: async reset (requires special scan cell)
always @(posedge clk or posedge rst) begin
  if (rst)
    q <= 1'b0;
  else
    q <= d;
end
```

- Use synchronous resets when possible (smaller scan cell overhead)
- If async reset is required, document it for DFT team
- Never create combinational feedback loops (unscannable)

## Memory BIST (MBIST)

### Concept

Built-in self-test for embedded memories. A controller generates addresses/data and compares read-back.

### RTL implications

- Memory ports must be accessible for BIST insertion
- Do not hard-wire memory write-enable to constant values
- Provide test-mode mux on memory address/data/enable inputs

```verilog
// BIST-ready memory interface
wire [AW-1:0] mem_addr = bist_en ? bist_addr : func_addr;
wire [DW-1:0] mem_wdata = bist_en ? bist_wdata : func_wdata;
wire          mem_wen   = bist_en ? bist_wen   : func_wen;
```

## Logic BIST (LBIST)

- Uses pseudo-random pattern generator (PRPG) and multiple-input signature register (MISR)
- Lower coverage than ATPG but at-speed testing
- RTL must support scan insertion in test mode

## JTAG / test access

- IEEE 1149.1 (JTAG) provides standard test access port
- TAP controller manages scan, BIST, and debug access
- RTL should expose test mode signals cleanly

## DFT checklist for RTL reviews

- [ ] All flops are scannable (no latches, no combinational loops)
- [ ] Memory ports have BIST mux capability
- [ ] Clock gating is overridden in test mode
- [ ] Async resets are documented for DFT team
- [ ] No tri-state buses without explicit enables
- [ ] Test mode signal is top-level accessible

## Common mistakes

1. Using latches as intentional state (breaks scan)
2. Gating clocks without test-mode bypass
3. Hard-wiring memory control signals (blocks BIST)
4. Async resets without DFT team coordination
5. Combinational feedback (unscannable, untestable)
