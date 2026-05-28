# Verification guidance

## Source policy

Use this guidance to reinforce standard verification practice rather than ad hoc habits.
Prefer methods that create a clear pass/fail signal.

## Verification hierarchy

1. Syntax and elaboration checks
2. Lint and style checks
3. Directed simulation
4. Assertion-based checks
5. Coverage review
6. Formal or equivalence checks when appropriate

## What to generate with RTL

When the user asks for RTL, also provide:

- a minimal directed test list
- a compact verification matrix for nontrivial stateful blocks
- at least one boundary test
- at least one handshake or stall test if relevant
- the key cycle trace expectations
- any assertions that should guard the contract

## Testbench priorities

A useful first-pass testbench should answer these questions:

- Does reset place the DUT in a known state?
- Does one normal transaction behave correctly?
- What happens at the boundary condition?
- What happens when the consumer stalls or the producer backpressures?
- Are data and control still aligned after a pause or flush?
- Can the test identify the first failing cycle or failing invariant?

## Assertion themes

- data stable while waiting for handshake acceptance
- state transitions only through legal paths
- FIFO never underflows or overflows in the intended protocol
- pipeline valid and payload stay aligned
- outputs obey reset contract
- cycle trace invariants are protected by at least one pass/fail check

## Executable fixture checks

When a fixture directory contains `manifest.json`, `dut.v`, and `tb.v`, use:

```bash
python scripts/rtl_check.py --case <fixture_dir>
```

The checker compiles with Icarus Verilog, runs the testbench with `vvp`, and compares the result with the fixture manifest.
For bug fixtures, an expected failing signature can be a successful checker result because the defect was reproduced.

Use checker output as evidence:

- quote the failing signature,
- name the violated contract,
- propose the smallest RTL fix,
- rerun the fixture after the fix when execution is available.

## Verification depth warning

Directed simulation is a useful first check, not signoff.
For integration-ready RTL, also call out missing lint, CDC, coverage, formal, synthesis, or timing checks when relevant.

## Minimum directed test count

For any nontrivial module (FSM, FIFO, protocol adapter, DMA channel, arbiter):

- **At least 5 directed tests** minimum before claiming "reviewable RTL"
- Must cover these categories: reset, normal operation, boundary, backpressure, error
- Each test must have explicit pass/fail criterion (not just waveform stimulus)
- If the spec defines N test cases, implement at least N/2 before claiming "reviewable RTL"
- For multi-channel designs, test each channel independently plus one cross-channel scenario

Insufficient test coverage is a common reason for undetected RTL bugs. A design that passes 3 basic tests but lacks boundary and error coverage is still at maturity level "Sketch", not "Reviewable RTL".

## Golden reference tier

Beyond directed tests, add golden reference checks for functional correctness:

| Tier | What it checks | When required | Example |
|------|---------------|---------------|---------|
| **T1: Structural** | Lint, naming, FSM style | Always (Step 8) | verilator --lint-only |
| **T2: Directed** | Happy path, boundary, stall | Always (Step 9) | 5+ directed tests |
| **T3: Golden reference** | Output values against known-good | Always (Step 8b) | CRC I/O pairs, register readback |
| **T4: Scoreboard** | End-to-end data integrity | Data movement modules | Input pattern == output pattern |
| **T5: Invariants** | Continuous property checking | Stateful modules | One-hot grant, credit bounds |

A design at T2 without T3 is at maturity level "Structural Sketch" — it compiles and runs, but functional correctness is unverified. T3 is the minimum for "Reviewable RTL."

**Rule:** If the module computes, transforms, routes, or stores data, it needs at least one T3 check. If it moves data end-to-end, it needs T4. If it manages state (arbiters, counters, FSMs), it needs T5.

See `references/verification/golden-reference-guide.md` for the full methodology and testbench templates.

## How the agent should respond to failures

- Quote the failing condition in plain language.
- Identify whether the bug is in contract, implementation, or test.
- Propose the smallest code or test change that isolates the issue.
- Ask for missing waveform evidence if the failure is ambiguous.
