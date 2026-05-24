# Hierarchical design guidelines

## Purpose

Use this file when the user asks for a complete subsystem or large RTL block.
Module-level cycle traces do not scale to full DMA engines, bus bridges, caches, NoCs, or multi-channel controllers.
For large systems, decompose first, trace risky boundaries locally, then implement one leaf or integration slice at a time.

## Request classification

Classify the request before writing RTL:

- Leaf module: one FSM, FIFO, register slice, pipeline stage, counter, arbiter, or adapter.
- Subsystem: multiple leaf modules with one primary data path or control path.
- Full system: multiple protocols, multiple channels, descriptor/status/error handling, or top-level integration.

Large-system trigger phrases include complete DMA, AXI subsystem, cache, NoC, bus bridge, multi-channel engine, memory engine, descriptor engine, full top, or full integration.

## Large-system rule

Do not emit full top-level RTL for a complex system in one pass.
Start with:

1. system contract,
2. submodule decomposition,
3. interface contracts,
4. integration invariants,
5. local cycle traces for risky boundaries,
6. staged implementation sequence,
7. verification strategy.

Only generate RTL for a selected leaf module or a narrow integration slice unless the user explicitly requests a staged implementation and the contracts are complete.
Use `staged-bringup-guidelines.md` for the implementation sequence and `verification-matrix-template.md` for test planning.

## Decomposition method

Split the design by behavior, not by file count:

- Control path: descriptor decode, command sequencing, state transitions, configuration, completion.
- Data path: read data, write data, width conversion, alignment, FIFOs, buffering.
- Protocol path: AXI or local bus channels, ready/valid adapters, outstanding transaction control.
- Status path: completion, writeback, interrupts, error reporting.
- Recovery path: reset, flush, abort, error drain, outstanding work cancellation.

Each submodule must have one clear owner for state and one clear reason to stall.

## Interface contract requirements

For each submodule boundary, state:

- producer and consumer,
- transfer condition,
- payload and sideband fields,
- ordering guarantees,
- backpressure direction,
- latency and buffering assumptions,
- reset and flush behavior,
- error behavior.

If a boundary cannot be described in these terms, do not write integration RTL yet.

## Local trace selection

Trace only the boundaries that can break system behavior:

- descriptor accepted while command queue is full,
- data FIFO full while AXI read channel continues,
- write response arrives after data path error,
- completion generated before all writes are acknowledged,
- flush or reset with outstanding work,
- interrupt raised before visible completion.

The trace should protect an integration invariant, not every register in the system.

## Integration self-review

Before finalizing a large-system response, check:

- Does every external protocol channel have an owner?
- Does every queue have a defined full and empty policy?
- Can backpressure create a closed wait cycle?
- Can an error leave outstanding work without a drain or abort policy?
- Is completion ordered after all externally visible writes?
- Is interrupt generated only after completion is visible?
- Is reset or flush behavior consistent across submodules?
