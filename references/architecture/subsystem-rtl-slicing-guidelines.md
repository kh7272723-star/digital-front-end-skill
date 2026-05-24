# Subsystem RTL slicing guidelines

## Purpose

Use this file to turn a large architecture plan into implementable RTL without generating a fragile monolithic top.
It complements `hierarchical-design-guidelines.md` by defining how to choose the next slice.

## Slice selection

Pick one slice that has:

- one clear external input contract,
- one clear external output contract,
- bounded state ownership,
- a small local testbench,
- stubs or simple models for neighbors,
- one or two integration invariants to protect.

Prefer vertical slices over isolated code when integration risk is high.
For example, a DMA first slice may connect descriptor acceptance, one command issue path, one response tracker, and a completion stub, while data movement remains modeled.
For completion-ordering risk, use `evals/trials/dma_completion_slice_trial` as the first executable slice.

## Do not implement full top when

- protocol feature set is not frozen,
- outstanding limits are unspecified,
- error policy is not defined,
- reset or abort with outstanding work is unclear,
- software-visible completion ordering is unclear,
- channel-level backpressure has not been traced,
- no checker exists for the most important integration invariant.

In these cases, produce architecture plus the next safe slice.

## Slice output format

For subsystem implementation, use:

1. slice goal,
2. assumptions and unsupported features,
3. neighbor stubs or models,
4. interface contracts,
5. state ownership,
6. local cycle traces,
7. RTL files to write now,
8. directed and scoreboard checks,
9. residual integration risks.

## Bring-up ladder

Recommended sequence:

1. reset and idle connectivity,
2. single command with no stalls,
3. independent channel stalls,
4. replacement or simultaneous movement cycles,
5. boundary sizes and alignment,
6. error response path,
7. abort/reset with outstanding work,
8. multiple descriptors or channels,
9. interrupt or completion ordering,
10. performance and fairness stress.

## Review questions

- What state is owned by this slice?
- What state is still modeled by a stub?
- Which invariant does the testbench check?
- Can a local pass hide a top-level deadlock?
- What is the next slice after this one passes?
