# AXI read ID scoreboard trial

## Source basis

- Protocol rules: Arm AMBA AXI and ACE protocol specification, Arm IHI 0022.
- Open-source implementation style reviewed for inspiration, not copied:
  - PULP `axi`: ID-aware scoreboards, ID remapping, and modular AXI components.
  - alexforencich `verilog-axi`: nonblocking crossbar and DMA components with ID/order protection concepts.
  - ZipCPU `wb2axip`: formal-oriented AXI outstanding and response checking style.

## Slice goal

Exercise multi-outstanding AXI read response tracking without building a full interconnect:

- ID width 2, four possible IDs.
- One outstanding burst per ID.
- Multiple IDs can be active at once.
- Different IDs may complete out of issue order.
- Same active ID cannot accept a second command.
- R beats are tracked by `RID`.
- `RLAST` alignment and `RRESP` errors are accumulated per ID.

## Contract

- `cmd_valid_i && cmd_ready_o` accepts a read command for `cmd_id_i`.
- `cmd_ready_o=0` when the selected ID already has an active burst or completion output is pending.
- `m_rready_o=1` only when `m_rid_i` names an active ID and no completion output is pending.
- Each accepted R beat decrements the remaining beat count for `m_rid_i`.
- `m_rlast_i` must match whether that ID's beat count is one.
- `done_valid_o` reports ID completion after that ID's final expected R beat.
- `done_error_o` reports accumulated non-OKAY `RRESP` or `RLAST` mismatch for that ID.

## Verification matrix

| Scenario | Stimulus | Expected result | Checker | Priority |
| --- | --- | --- | --- | --- |
| multi-ID issue | accept ID0 then ID1 | both IDs active | direct counters | high |
| same-ID block | issue ID0 while ID0 active | `cmd_ready_o=0` | direct check | high |
| out-of-order completion | complete ID1 before ID0 | done reports ID1 first | direct check | high |
| inactive ID response | drive RID with no active burst | `m_rready_o=0` | direct check | high |
| RLAST mismatch | early `RLAST` on ID2 | final done has error | direct check | high |
| RRESP error | non-OKAY response on ID3 | final done has error | direct check | high |

## Run

```text
python scripts/rtl_check.py --case evals/trials/axi_read_id_scoreboard_trial
```
