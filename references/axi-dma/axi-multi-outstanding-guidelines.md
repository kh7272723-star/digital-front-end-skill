# AXI multi-outstanding guidelines

## Purpose

Use this file when AXI full work requires multiple IDs, multiple outstanding transactions, or out-of-order completion across IDs.
This guidance is distilled from Arm AMBA AXI transaction ID and ordering rules, with implementation style informed by PULP `axi`, alexforencich `verilog-axi`, and ZipCPU `wb2axip`.

## Scope discipline

Do not jump from a single-ID slice to a full interconnect.
First define:

- supported ID width,
- maximum outstanding transactions per ID,
- maximum total outstanding transactions,
- whether same-ID reordering is allowed,
- whether interleaved read data across IDs is accepted by this block,
- how completions are reported,
- what happens on unknown ID responses.

## Conservative tracking rule

For a first multi-outstanding slice:

- allow multiple IDs to be outstanding,
- allow completions for different IDs to occur in different order from command issue order,
- restrict each ID to one outstanding burst,
- track remaining beats and accumulated error per ID,
- complete an ID when its final expected beat is accepted,
- block a new command for an ID that is already active.

This avoids same-ID ordering ambiguity while exercising true multi-ID scoreboard behavior.

## Required cycle rows

Include rows for:

- command for ID0 accepted,
- command for ID1 accepted before ID0 completes,
- response for ID1 completes before ID0,
- response for inactive ID is not accepted,
- early or missing `RLAST` marks error without early completion,
- new command for active ID is blocked.

## Verification minimum

Include checks for:

- outstanding count per ID,
- command blocked when same ID already active,
- cross-ID out-of-order completion accepted,
- `RLAST` alignment per ID,
- `RRESP` error accumulation per ID,
- no counter underflow on inactive ID response.

## Golden fixture

Use `evals/trials/axi_read_id_scoreboard_trial` as the executable local example.
Run:

```text
python scripts/rtl_check.py --case evals/trials/axi_read_id_scoreboard_trial
```
