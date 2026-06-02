# Protocol authority map

## Purpose

Use this file before adding or changing protocol-specific rules.
Protocol guidance in this skill should be distilled from official standards or project-owned specifications, not from random code examples.

Protocol reference files must separate specification facts from local engineering policy. A rule can be written as a hard requirement only when it is marked **Normative** and tied to an official source or user-provided spec.

## Source priority

1. User-provided project protocol specification.
2. Official protocol specification from the owner of the protocol.
3. Official vendor integration guide for a specific IP or tool flow.
4. Local verified fixture in this skill.
5. Third-party tutorials only as explanatory aids, never as authority.

## Open-source example policy

Use mature open-source RTL to study structure, test strategy, and common decomposition patterns.
Do not copy implementation text into this skill unless the license is compatible and the copied boundary is explicit.
Prefer writing small independent fixtures that implement the official protocol rule being taught.

Good use:

- compare handshake and buffering structure,
- learn which corner cases mature projects test,
- cite the repository as inspiration in fixture README files.

Bad use:

- paste a large module and relabel it,
- mix incompatible license terms into local examples,
- let open-source implementation choices override official protocol semantics.

## AMBA sources

Use Arm official AMBA documentation for AXI, AXI-Lite, AXI-Stream, APB, AHB, ACE, and CHI work.

- AMBA specifications index: `https://www.arm.com/architecture/system-architectures/amba/amba-specifications`
- AMBA AXI and ACE Protocol Specification, Arm IHI 0022: `https://developer.arm.com/documentation/ihi0022`
- AMBA APB Protocol Specification, Arm IHI 0024: `https://developer.arm.com/documentation/ihi0024`
- AMBA AHB Protocol Specification, Arm IHI 0033: `https://developer.arm.com/documentation/ihi0033`
- AMBA AXI4-Stream Protocol Specification, Arm IHI 0051: `https://developer.arm.com/documentation/ihi0051`

## Open-source examples worth studying

- alexforencich `verilog-axis`: AXI-Stream components and cocotb-based tests, useful for stream buffers, adapters, and packet-aware components.
- PULP `axi_stream`: SystemVerilog AXI-Stream components with composable high-performance stream design style.
- PULP `common_cells`: ready/valid stream registers, spill registers, and arbiters useful for microarchitecture patterns.
- Roa Logic AHB-Lite documentation and examples: useful for AHB-Lite interconnect and peripheral integration concepts; check license before reuse.

## How to distill a protocol rule

For each protocol rule, record:

- source protocol and version family,
- affected channel or signal group,
- allowed transaction ordering,
- stable-while-waiting requirement,
- response or error timing,
- RTL state needed to implement it,
- verification check that would catch a violation.

## Authority labels

Use one of these labels for every protocol-specific `must`, `shall`, `required`, or `violation` statement:

| Label | Meaning | Allowed wording |
| --- | --- | --- |
| **Normative** | Direct protocol requirement from the selected official spec or user spec. | `must`, `shall`, `protocol violation` |
| **Project policy** | Local contract chosen for this design, stricter than or narrower than the protocol. | `local requirement`, `project requires` |
| **Conservative pattern** | Recommended RTL pattern that avoids common bugs but is not the only legal protocol implementation. | `recommended`, `safe default`, `prefer` |
| **Heuristic** | Experience-based design guidance or performance advice. | `usually`, `often`, `watch for` |
| **Unverified** | Claim not yet checked against a primary source. | never use `must`; mark as a question or remove |

Do not convert a **Conservative pattern** into a **Normative** rule. This was the root cause of the P12 WVALID error: a fully-buffered, continuous-WVALID implementation policy was incorrectly described as an AXI protocol requirement for every burst.

## Known correction: AXI WVALID within a burst

Arm AMBA AXI defines VALID/READY stability per transfer item: once a source asserts VALID for an address, data, or control item, VALID and its associated information remain stable until the handshake occurs. The AXI rule does **not** by itself require WVALID to remain continuously asserted from the first accepted W beat through WLAST.

Therefore:

- **Normative:** if `WVALID=1` and `WREADY=0`, hold `WVALID`, `WDATA`, `WSTRB`, and `WLAST` stable until that beat handshakes.
- **Normative:** advance the W beat counter only on `WVALID && WREADY`; assert `WLAST` on the final accepted beat.
- **Conservative pattern:** require a full-burst buffer before asserting the first W beat, then keep WVALID continuous through WLAST.
- **Project policy:** a DMA design may choose continuous WVALID to simplify timing and verification, but the contract must say so explicitly.
- **Heuristic:** WVALID bubbles between accepted beats are legal only if the design's selected contract allows elastic W data and the design proves no data is lost, duplicated, or deadlocked.

## Rule conflicts

If local project rules conflict with this skill:

- follow the project rule,
- state the conflict,
- keep the official protocol requirement visible,
- do not hide a protocol waiver inside generated RTL.
