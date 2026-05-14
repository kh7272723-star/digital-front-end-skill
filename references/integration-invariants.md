# Integration invariants

## Purpose

Use integration invariants to reason about large RTL systems.
These invariants replace the impossible goal of tracing every register in a large design.

## Core invariants

- No data loss: every accepted input item is either completed, reported as an error, or explicitly aborted.
- No data duplication: one accepted item cannot produce more than one completion unless the contract says so.
- No early completion: completion is generated only after required externally visible writes or responses have occurred.
- No early interrupt: interrupt is generated only after completion state is visible to software.
- No closed backpressure wait cycle: a set of modules must not wait on each other forever with no state-changing event.
- Bounded outstanding work: counters, tags, and queues must limit accepted work to available tracking resources.
- Ordered writeback: status writeback must not pass the data movement it reports.
- Error convergence: error paths must drain, abort, or block new work according to a stated policy.
- Reset convergence: after reset release, all submodules agree on idle, empty, invalid, and no-outstanding state.
- Sideband alignment: IDs, byte enables, error flags, and addresses stay aligned with their payloads.

## Invariant format

Write invariants as checkable statements:

```text
Invariant:
Trigger:
Protected state:
Failure symptom:
Directed test:
Assertion or monitor idea:
```

## Deadlock review

For each backpressure path, identify:

- source of pressure,
- propagation direction,
- buffer or queue that can absorb it,
- state transition that can relieve it,
- condition that can permanently block relief.

If there is no relief condition, the architecture is not ready for integration RTL.
