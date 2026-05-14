# Arbiter examples

## Purpose

Use this reference when generating or reviewing priority, round-robin, or backpressured ready/valid arbiters.
Arbiters are small enough to look simple, but they often fail at stall, grant-hold, pointer-update, and fairness boundaries.

## Contract checklist

- Number of requesters and grant encoding.
- Whether request data is combinationally selected or registered.
- Whether a grant may change while the downstream side is stalled.
- Exact pointer update condition.
- Reset priority and first grant after reset.
- Whether invalid requesters are skipped.
- Starvation expectation and assumptions needed for fairness.
- Backpressure direction and whether unselected requesters can remain asserted.

## Registered ready/valid round-robin pattern

The golden fixture is:

- `evals/trials/rr_arbiter_trial/README.md`
- `evals/trials/rr_arbiter_trial/rr_ready_valid_arbiter.v`
- `evals/trials/rr_arbiter_trial/tb.v`

Behavioral rules from the fixture:

- The output slot is a registered item.
- If `valid_o && !ready_i`, `valid_o`, `data_o`, and `grant_o` hold stable.
- While the output slot is full and stalled, `ready_o` is zero for every requester.
- If the output slot is empty or being accepted by the downstream side, one valid requester may be accepted.
- The search starts at `rr_ptr_q` and wraps around.
- `rr_ptr_q` advances only after an input item is accepted.
- The requester after the accepted requester is searched first on the next acceptance opportunity.

## Required cycle rows

At minimum, show rows for:

- reset release,
- first request after reset,
- downstream stall,
- consume and replace in the same edge,
- consume with no replacement,
- sparse requester mask,
- persistent all-requester fairness window.

## Verification minimum

For nontrivial arbiter RTL, include these checks:

- zero-or-one-hot ready/grant acceptance,
- expected grant order for all-requester traffic,
- skip behavior for sparse requester masks,
- output payload and sideband stability under downstream stall,
- scoreboard comparison for mixed valid/ready traffic,
- bounded fairness counter for persistent requesters,
- timeout or liveness check when the environment is expected to make progress.

Simulation does not prove fairness for every possible environment.
If fairness is a signoff requirement, add formal assumptions for persistent requests and downstream progress, then prove no persistent requester is starved within the stated bound.
