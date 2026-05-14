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

## How the agent should respond to failures

- Quote the failing condition in plain language.
- Identify whether the bug is in contract, implementation, or test.
- Propose the smallest code or test change that isolates the issue.
- Ask for missing waveform evidence if the failure is ambiguous.
