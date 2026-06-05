# Protocol authority audit

## Purpose

Use this file when reviewing or updating protocol material in this skill. Its job is to prevent "authoritative distillation drift": a local implementation preference, fixture shortcut, or incomplete project observation being rewritten as a protocol rule.

## Required audit steps

For every protocol-specific reference file:

1. List the protocol version and primary source at the top of the file.
2. Mark every hard statement as **Normative**, **Project policy**, **Conservative pattern**, **Heuristic**, or **Unverified**. A statement that uses `must`, `shall`, `spec requires`, `protocol violation`, `required`, or `no provision for` without one of these labels is **unreviewed** and must be treated as Unverified.
3. Replace unsupported `must`, `shall`, `required`, and `violation` wording with the correct label.
4. Check that assertions and testbench checks match the exact rule being claimed — not a stronger or weaker version.
5. Check that testbenches verify both data values and protocol shape: transaction count, address sequence, burst length, last-beat markers, byte enables, responses, and completion ordering.
6. For every `must`/`shall` claim citing an Arm AMBA or NVMe spec: verify the exact section number and wording against the primary source. If the section doesn't say what the reference claims, downgrade to Conservative pattern or Heuristic.

## Primary source index

| Protocol | Primary source |
| --- | --- |
| AXI full / AXI-Lite | Arm AMBA AXI and ACE Protocol Specification, IHI 0022 |
| AXI-Stream | Arm AMBA AXI4-Stream Protocol Specification, IHI 0051 |
| APB | Arm AMBA APB Protocol Specification, IHI 0024 |
| AHB | Arm AMBA AHB Protocol Specification, IHI 0033 |
| NVMe | NVM Express Base Specification 2.3 and NVM Command Set Specification 1.2 |

## Corrections from this audit

### AXI WVALID within bursts

Previous local guidance incorrectly stated that AXI requires WVALID to remain asserted continuously from the first W beat through WLAST. Corrected rule:

- **Normative:** once a W beat is presented with `WVALID=1`, keep `WVALID`, `WDATA`, `WSTRB`, and `WLAST` stable until `WREADY` completes that beat.
- **Local policy:** a design may require continuous WVALID across a burst, but then it must document continuous/full-burst-buffered mode and check full-burst data availability before start.
- **Elastic policy:** a design may allow bubbles between accepted W beats if the contract declares elastic mode and verifies no underflow, no data loss, correct beat count, and local liveness.

### DMA verification scope

Previous local examples allowed a data-only scoreboard to imply DMA correctness. Corrected rule: DMA testbenches must check the AXI transaction shape and response/completion ordering in addition to payload data.

### NVMe queue and PRP distillation

Previous local NVMe guidance mixed generic ring-buffer assumptions with NVMe phase-tag semantics. Corrected rule:

- NVMe queue entry pointers wrap modulo queue size; CQ Phase Tag distinguishes new completions after CQ wrap and does not make pointers count to `2*depth`.
- NVMe QSIZE fields are zero-based; internal queue depth is `QSIZE + 1`.
- PRP List entries are packed from entry 0; the last entry before the end of a list page is a chain pointer only when another PRP List page is required.

## Red flags

Treat these phrases as review triggers:

- "the spec requires" without protocol version or section
- "no provision for" without a primary-source check
- "always a protocol violation" for behavior that might be a local mode choice
- testbench "PASS" based only on captured data, without expected transaction count
- NVMe queue math using linear pointer subtraction without wrap handling
