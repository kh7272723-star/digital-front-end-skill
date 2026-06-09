# CDC Asymmetric Gray-Code Reference

## Summary

When an asynchronous FIFO uses asymmetric read/write widths with a ratio
`RATIO > 1`, the read pointer increments by `RATIO` entries per read operation
rather than by 1.  This causes multi-bit transitions in the Gray-code
representation between consecutive pointer values, which deviates from the
single-bit-change guarantee relied upon by the standard Cliff Cummings
(SNUG 2002) asynchronous FIFO CDC scheme.

## Background

The Cummings async FIFO uses Gray-coded pointers crossing clock domains
through 2-FF synchronisers.  The safety guarantee is: **each Gray-code
transition toggles exactly one bit**, so the synchroniser always captures
either the old or the new value — never a metastable hybrid.

This holds when pointers increment by 1.  When they increment by `RATIO`
(a power of 2), the Gray code of `ptr + RATIO` may differ by **multiple
bits** from the Gray code of `ptr`.

## Example (RATIO = 4, ptr = 5 bits)

| Binary | Gray | Bits flipped from previous |
|--------|------|---------------------------|
| 0_0000 | 0_0000 | — |
| 0_0100 | 0_0110 | 2 bits (1, 2) |
| 0_1000 | 0_1100 | 2 bits (2, 3) |
| 0_1100 | 0_1010 | 2 bits (1, 3) |
| 1_0000 | 1_1000 | 2 bits (2, 3) |

## Risk Assessment

**Severity: Low-Medium.**  In practice the 2-FF synchroniser still captures
either the pre-transition or post-transition value (or enters metastability
resolving to one of them).  The full/empty detection formulas are conservative,
so a stale synchronised value does not cause overflow or underflow — it only
delays the flag assertion by 2-3 clock cycles.

## Design Requirements

1. **Document the limitation** in the project's timing contract or interface
   contracts, referencing this file.
2. **Use `(* ASYNC_REG = "TRUE" *)`** on all synchroniser stages.
3. **Prefer depths and ratios that are powers of 2** to keep CDC skew
   deterministic.
4. **Verify with randomised clock-phase simulation** (non-aligned wr_clk and
   rd_clk edges, jitter/variation in clock periods).
5. **For safety-critical applications**, consider:
   - Using a single-bit synchroniser per Gray bit with handshake
   - Using a credit-based flow-control scheme instead of pointer comparison

## References

- Cummings, C.E. "Simulation and Synthesis Techniques for Asynchronous
  FIFO Design." SNUG San Jose, 2002.
- Cummings, C.E. "Synthesis and Scripting Techniques for Designing
  Multi-Asynchronous Clock Designs." SNUG San Jose, 2001.

## Related Skill Checks

- `rtl_style_check.py`: C17_ARR1 (unpacked array for FIFO storage)
- `workflow_gate.py`: pre-rtl gate requires timing-contract.md to cite this
  reference when RATIO > 1 is detected.
