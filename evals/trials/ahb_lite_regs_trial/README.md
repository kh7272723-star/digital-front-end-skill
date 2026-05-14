# AHB-Lite register block trial

## Source basis

- Protocol rules: Arm AMBA AHB protocol specification, Arm IHI 0033.
- Implementation style: simple register-slave structure inspired by common vendor AHB-Lite peripheral templates and open-source interconnect examples, but RTL here is written independently.

## Contract

- Single AHB-Lite style subordinate, one clock `clk_i`, synchronous active-high reset `rst_i`.
- Supported transfers are `NONSEQ` and `SEQ` where `htrans_i[1]=1`.
- Address/control phase is accepted when `hsel_i && hready_i && hready_o && htrans_i[1]`.
- Data phase uses the registered address/control from the previous accepted address phase.
- `hready_o=0` inserts one wait cycle for the current data phase.
- Writes update registers only when the registered data phase completes.
- Reads return data for the registered data phase.
- Only word-size accesses to addresses `0x0` and `0x4` are supported; invalid address or size returns error and does not update state.

## State elements

- `data_valid_q`: active data phase exists.
- `data_addr_q`, `data_write_q`, `data_size_q`, `data_error_q`: registered previous address/control phase.
- `wait_q`: one-cycle data-phase wait request.
- `reg0_q`, `reg1_q`: register state.

## Cycle trace

| Cycle | Pre-edge state | Combinational condition | Active-edge update | Next visible state | Invariant |
| --- | --- | --- | --- | --- | --- |
| reset | state unknown, `rst_i=1` | reset branch selected | clear registers and data phase | ready, no data phase | no false access |
| address phase | no wait, active transfer | `accept_addr=1` | capture address/control | data phase active next cycle | data phase uses captured controls |
| write data phase | captured write to reg0 | `complete_data=1` | write `hwdata_i` to reg0 | reg0 updated | current HADDR must not redirect write |
| wait state | data phase active, `wait_q=1` | `hready_o=0` | clear wait request only | no register update | wait holds data phase |
| read data phase | captured read | `complete_data=1` | no state update | `hrdata_o` matches captured address | read uses previous address |
| error phase | captured invalid access | `hresp_o=1` on completion | no write update | error visible | invalid access protects state |

## Verification matrix

| Scenario | Stimulus | Expected result | Checker | Coverage target | Priority |
| --- | --- | --- | --- | --- | --- |
| reset | assert and release reset | ready, registers zero | direct check | reset release | high |
| phase alignment | write address reg0, then change HADDR to reg1 during data phase | reg0 updates, reg1 unchanged | direct check | previous address phase | high |
| wait state | accepted write with wait request | no update while `hready_o=0` | direct check | one wait cycle | high |
| read phase | read reg0/reg1 | expected data returned | direct check | read data phase | high |
| invalid address | write/read invalid address | error, no state update | direct check | decode error | high |
| unsupported size | halfword write | error, no state update | direct check | size error | medium |

## Run

```text
python scripts/rtl_check.py --case evals/trials/ahb_lite_regs_trial
```
