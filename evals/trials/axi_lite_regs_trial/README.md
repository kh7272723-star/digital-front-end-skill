# AXI-Lite register block trial

## Assumptions

- Plain Verilog-first RTL.
- Single clock `clk_i`.
- Synchronous active-high reset `rst_i`.
- Conservative AXI-Lite subset: one outstanding write and one outstanding read.
- Write address and write data are independent and may arrive in either order.
- Read data and write response are registered and held under backpressure.

## Contract

- `awvalid_i && awready_o` accepts one write address.
- `wvalid_i && wready_o` accepts one write data payload and byte strobe.
- A write updates a register only after both address and data have been accepted.
- `bvalid_o` asserts after the write is executed or rejected, and `bresp_o` holds until `bready_i`.
- `arvalid_i && arready_o` accepts one read address.
- `rvalid_o`, `rdata_o`, and `rresp_o` hold until `rready_i`.
- Invalid write addresses return error response and do not update registers.
- Invalid read addresses return error response and zero data.

## State elements

- `reg0_q`, `reg1_q`: visible register state.
- `aw_hold_valid_q`, `awaddr_q`: stored write address.
- `w_hold_valid_q`, `wdata_q`, `wstrb_q`: stored write data.
- `bvalid_o`, `bresp_o`: registered write response.
- `rvalid_o`, `rdata_o`, `rresp_o`: registered read response.

## Cycle trace

| Cycle | Pre-edge state | Combinational condition | Active-edge update | Next visible state | Invariant |
| --- | --- | --- | --- | --- | --- |
| reset | state unknown, `rst_i=1` | reset branch selected | clear valid flags and registers | no response visible | reset creates no false response |
| AW before W | no stored write data | address accepted, data missing | store address only | no B response yet | write waits for both halves |
| W before AW | no stored address | data accepted, address missing | store data only | no B response yet | write waits for both halves |
| AW and W complete | one half stored or both accepted | both halves available | update decoded register, set B | B response visible | one write creates one response |
| B stall | `bvalid_o=1`, `bready_i=0` | response not accepted | hold response | B remains visible | response stable under backpressure |
| read accept | `rvalid_o=0` | AR accepted | capture read data and response | R response visible | read returns decoded state |
| R stall | `rvalid_o=1`, `rready_i=0` | response not accepted | hold response | R remains visible | data and response stable |

## Verification matrix

| Scenario | Stimulus | Expected result | Checker | Coverage target | Priority |
| --- | --- | --- | --- | --- | --- |
| reset | assert and release reset | registers and responses clear | direct checks | first active cycle | high |
| AW before W | address first, data later | write occurs only after data | readback check | independent write channels | high |
| W before AW | data first, address later | write occurs only after address | readback check | reverse write order | high |
| byte strobe | write selected byte lanes | only selected bytes update | readback check | partial write | high |
| B backpressure | hold `bready_i=0` | `bvalid_o/bresp_o` stable | stability check | response hold | high |
| R backpressure | hold `rready_i=0` | `rvalid_o/rdata_o/rresp_o` stable | stability check | read hold | high |
| invalid address | access unmapped address | error response, no state update | response and readback checks | decode error | medium |

## Run

```text
python scripts/rtl_check.py --case evals/trials/axi_lite_regs_trial
```
