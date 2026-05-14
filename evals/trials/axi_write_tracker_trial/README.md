# AXI full write tracker trial

## Source basis

- Protocol rules: Arm AMBA AXI and ACE protocol specification, Arm IHI 0022.
- Open-source implementation style reviewed for inspiration, not copied:
  - PULP `axi`: modular AXI channel handling and verification-oriented components.
  - alexforencich `verilog-axi`: practical AXI component decomposition and testbench style.
  - ZipCPU `wb2axip`: formal-oriented AXI/AXI-Lite examples and response-order thinking.

## Slice goal

Implement one bounded AXI full write slice:

- single ID,
- one outstanding write burst,
- AW issued and held until accepted,
- W beats issued after AW acceptance,
- `WLAST` generated only on the final accepted W beat,
- completion waits for B response,
- non-OKAY B response is reported as error.

This is not a full AXI master. It omits address generation, data payload, strobes, IDs, burst type, and multiple outstanding transactions.

## Contract

- `cmd_valid_i && cmd_ready_o` accepts one write command.
- `cmd_awlen_i` uses AXI encoding: number of beats minus one.
- `m_awvalid_o` holds until `m_awready_i=1`.
- W beats start only after AW acceptance in this conservative slice.
- `m_wvalid_o && m_wready_i` accepts one W beat.
- `m_wlast_o` is high only when the accepted W beat is the final beat of the burst.
- `m_bready_o` is high only after AW is accepted and all W beats are accepted.
- `done_valid_o` asserts only after a B response is accepted.
- `error_o` captures `m_bresp_i != OKAY` on accepted B response.

## State elements

- `active_q`: burst in progress.
- `aw_done_q`: AW channel accepted.
- `awlen_q`: stored AXI length field.
- `beats_rem_q`: remaining W beats.
- `done_valid_o`, `error_o`: completion result.

## Cycle trace

| Cycle | Pre-edge state | Combinational condition | Active-edge update | Next visible state | Invariant |
| --- | --- | --- | --- | --- | --- |
| reset | state unknown, `rst_i=1` | reset branch selected | clear active and done | idle | no false command or done |
| command accept | idle, command valid | `accept_cmd=1` | load AWLEN, set active, set beat count | AW pending | command creates one burst |
| AW stall | AW pending, `m_awready_i=0` | `accept_aw=0` | hold AW fields | AW still valid | AW payload stable while waiting |
| AW accept | AW pending, `m_awready_i=1` | `accept_aw=1` | set `aw_done_q` | W path may issue | W starts after AW in this slice |
| W middle beat | beats remaining > 1 | `accept_w=1`, `m_wlast_o=0` | decrement beat count | more W beats pending | no early last |
| final W beat | beats remaining = 1 | `accept_w=1`, `m_wlast_o=1` | decrement to zero | wait for B | last data beat is not completion |
| B delayed | W done, `m_bvalid_i=0` | `accept_b=0` | hold active | no completion | completion waits for B |
| B accept | W done, `m_bvalid_i=1` | `accept_b=1` | clear active, set done/error | done visible | B response completes burst |

## Verification matrix

| Scenario | Stimulus | Expected result | Checker | Coverage target | Priority |
| --- | --- | --- | --- | --- | --- |
| reset | assert and release reset | idle and ready | direct checks | reset release | high |
| AW stall | command accepted, AWREADY low | AWVALID and AWLEN hold | stability check | two-cycle AW stall | high |
| W beat count | 4-beat burst | WLAST only on fourth accepted beat | directed checks | AWLEN=3 | high |
| W backpressure | WREADY low during burst | beat count and WLAST hold | direct checks | one-cycle W stall | high |
| B delayed | final W accepted, BVALID low | no done yet | direct check | delayed response | high |
| B error | BRESP non-OKAY | done with error | direct check | error response | high |
| single beat | AWLEN=0 | first W beat has WLAST | direct check | one-beat burst | medium |

## Run

```text
python scripts/rtl_check.py --case evals/trials/axi_write_tracker_trial
```
