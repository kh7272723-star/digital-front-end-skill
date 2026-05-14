# AXI full read tracker trial

## Source basis

- Protocol rules: Arm AMBA AXI and ACE protocol specification, Arm IHI 0022.
- Open-source implementation style reviewed for inspiration, not copied:
  - PULP `axi`: modular AXI channel handling and verification-oriented components.
  - alexforencich `verilog-axi`: practical AXI component decomposition and testbench style.
  - ZipCPU `wb2axip`: formal-oriented AXI/AXI-Lite examples and response-order thinking.

## Slice goal

Implement one bounded AXI full read slice:

- single ID,
- one outstanding read burst,
- AR issued and held until accepted,
- R beats accepted after AR acceptance,
- expected beat count derives from ARLEN plus one,
- `RLAST` must align with the final expected accepted R beat,
- non-OKAY `RRESP` is captured as error,
- completion waits for the final expected accepted R beat.

This is not a full AXI master. It omits address generation, data payload storage, IDs, burst type, multiple outstanding transactions, and out-of-order response handling.

## Contract

- `cmd_valid_i && cmd_ready_o` accepts one read command.
- `cmd_arlen_i` uses AXI encoding: number of beats minus one.
- `m_arvalid_o` and `m_arlen_o` hold until `m_arready_i=1`.
- R beats are accepted only after AR acceptance.
- `m_rready_o` follows local `rdata_ready_i` only while a read burst is active.
- `m_rvalid_i && m_rready_o` accepts one R beat.
- `m_rlast_i` must be high only on the final expected R beat.
- Any non-OKAY `m_rresp_i` or `RLAST` mismatch sets `error_o`.
- `done_valid_o` asserts after the final expected R beat is accepted and holds until `done_ready_i=1`.

## State elements

- `active_q`: read burst in progress.
- `ar_done_q`: AR channel accepted.
- `arlen_q`: stored AXI length field.
- `beats_rem_q`: remaining expected R beats.
- `error_q`: accumulated response or `RLAST` error.
- `done_valid_o`, `error_o`: visible completion result.

## Cycle trace

| Cycle | Pre-edge state | Combinational condition | Active-edge update | Next visible state | Invariant |
| --- | --- | --- | --- | --- | --- |
| reset | state unknown, `rst_i=1` | reset branch selected | clear active and done | idle | no false command or done |
| command accept | idle, command valid | `accept_cmd=1` | load ARLEN and beat count | AR pending | command creates one read burst |
| AR stall | AR pending, `m_arready_i=0` | `accept_ar=0` | hold AR fields | AR still valid | AR payload stable while waiting |
| AR accept | AR pending, `m_arready_i=1` | `accept_ar=1` | set `ar_done_q` | R path may accept | R starts after AR in this slice |
| R middle beat | beats remaining > 1 | `accept_r=1`, expected `RLAST=0` | decrement beat count | more R beats pending | no early completion |
| R backpressure | R valid, local sink not ready | `m_rready_o=0`, `accept_r=0` | no beat count update | same beat expected | stalled R does not advance state |
| final R beat | beats remaining = 1 | `accept_r=1`, expected `RLAST=1` | decrement to zero, set done | done visible | completion follows final accepted R |
| R error | accepted beat has non-OKAY response or wrong `RLAST` | `accept_r=1` | set error and keep draining | done later reports error | errors do not skip expected beats |

## Verification matrix

| Scenario | Stimulus | Expected result | Checker | Coverage target | Priority |
| --- | --- | --- | --- | --- | --- |
| reset | assert and release reset | idle and ready | direct checks | reset release | high |
| AR stall | command accepted, ARREADY low | ARVALID and ARLEN hold | stability check | two-cycle AR stall | high |
| R before AR | RVALID before AR acceptance | RREADY stays low | direct check | channel sequencing | high |
| R beat count | 4-beat burst | done after fourth accepted R beat | directed checks | ARLEN=3 | high |
| R backpressure | local data ready low | beat count does not change | direct check | one-cycle R stall | high |
| RRESP error | final beat has non-OKAY response | done with error | direct check | response error | high |
| RLAST mismatch | early RLAST before final expected beat | no early done, final done with error | directed check | last alignment | high |

## Run

```text
python scripts/rtl_check.py --case evals/trials/axi_read_tracker_trial
```
