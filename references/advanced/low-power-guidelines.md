# Low-Power Design Guidelines

## Purpose

This file covers low-power digital design techniques for RTL engineers. Use when the task involves power optimization, clock gating, power domains, or power-aware verification.

## Power reduction hierarchy

1. **Clock gating** — disable clocks to idle logic (highest ROI, lowest risk)
2. **Operand isolation** — disable inputs to combinational blocks when output is unused
3. **Power gating** — cut power to entire blocks (requires retention/isolation cells)
4. **Dynamic voltage/frequency scaling** — adjust V/F at runtime (system-level)

## Clock gating

### When to gate

- Register banks with stable inputs for multiple cycles
- FSM idle states with no pending work
- FIFO empty with no write expected
- Pipeline stages with no valid data

### RTL pattern

```verilog
// Enable-gated clock (synthesis-friendly)
wire gated_clk = clk_i & clk_en_i;

// Preferred: use ICG cell (tool infers this from enable)
reg clk_en_latch;
always @(*) begin
  if (!clk_i)
    clk_en_latch = clk_en_i;
end
wire gated_clk = clk_i & clk_en_latch;
```

### Rules

- Gate at the source, not downstream (reduces switching on the clock tree)
- Never gate clocks used for CDC synchronizers
- Never gate reset clocks
- Use enable signals, not gated clocks, in RTL (synthesis tool inserts ICG)
- Verify gated domain does not lose state on re-entry

## Operand isolation

```verilog
// Isolate multiplier inputs when result is unused
wire [31:0] a_isolated = result_needed ? a_i : 32'b0;
wire [31:0] b_isolated = result_needed ? b_i : 32'b0;
wire [31:0] product = a_isolated * b_isolated;
```

## Power domains

### Concepts

- **Always-on domain**: power management controller, wake-up logic, isolation cells
- **Switchable domain**: functional logic that can be powered off
- **Retention domain**: flip-flops that retain state during power-off (balloon flops)

### RTL implications

- Insert isolation cells at domain boundaries (clamp to 0 or hold)
- Use retention flops for state that must survive power-off
- Model power states in testbench (do not assume always-on)

## UPF/CPF basics

- UPF (Unified Power Format) describes power intent to synthesis/verification tools
- Key elements: power domains, power switches, isolation strategies, level shifters
- RTL must be power-intent-agnostic; UPF is a separate specification
- Verification: use UPF-aware simulation to check isolation and retention behavior

## Verification checklist

- [ ] Clock gating does not affect CDC synchronizers
- [ ] Gated domains retain or correctly re-initialize state
- [ ] Isolation cells clamp outputs when domain is off
- [ ] Wake-up latency meets system requirements
- [ ] Power transitions do not create glitches on active-domain signals

## Common mistakes

1. Gating a clock used by a synchronizer (breaks CDC)
2. Not verifying re-initialization after power-on (stale state)
3. Forgetting isolation at domain boundaries (contention)
4. Assuming combinational paths through powered-off domains are safe
