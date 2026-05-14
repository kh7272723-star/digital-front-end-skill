# APB register block trial

## Assumptions

- Plain Verilog-first RTL.
- Single clock `clk_i`.
- Synchronous active-high reset `rst_i`.
- APB-style slave with setup and access phases.
- `wait_i` models a slave wait state by lowering `pready_o`.
- Two 32-bit registers at addresses `0x0` and `0x4`.

## Contract

- Setup phase is `psel_i=1` and `penable_i=0`.
- Access phase is `psel_i=1` and `penable_i=1`.
- Completed access is `psel_i && penable_i && pready_o`.
- Writes update state only on completed write access.
- `pstrb_i` updates only selected byte lanes.
- Reads return register data on completed read access.
- Invalid addresses raise `pslverr_o` on completed access and writes do not update state.

## Cycle trace

| Cycle | Pre-edge state | Combinational condition | Active-edge update | Next visible state | Invariant |
| --- | --- | --- | --- | --- | --- |
| reset | state unknown, `rst_i=1` | reset branch selected | clear registers | registers zero | no false access |
| setup write | `psel_i=1`, `penable_i=0` | not completed access | no update | register unchanged | setup phase never writes |
| wait access | access phase, `wait_i=1` | `pready_o=0` | no update | register unchanged | wait state prevents transfer |
| complete write | access phase, `wait_i=0` | completed write access | update selected byte lanes | register updated | update happens once |
| complete read | access phase, `wait_i=0` | completed read access | no state update | `prdata_o` valid | read has no side effect |
| invalid write | access phase invalid address | completed access with error | no register update | `pslverr_o=1` | decode error protects state |

## Verification matrix

| Scenario | Stimulus | Expected result | Checker | Coverage target | Priority |
| --- | --- | --- | --- | --- | --- |
| reset | assert and release reset | registers clear | direct checks | reset release | high |
| setup phase | drive write setup | no state update | direct checks | setup-only cycle | high |
| wait state | access with `wait_i=1` | no state update | direct checks | one wait cycle | high |
| write complete | access with `wait_i=0` | selected register updates | readback/direct check | full write | high |
| byte strobe | partial write | selected lanes update | readback/direct check | byte lane | high |
| read complete | valid read access | data returned, no error | direct check | register read | high |
| invalid address | invalid read/write | error response, no write update | direct check | decode error | medium |

## Run

```text
python scripts/rtl_check.py --case evals/trials/apb_regs_trial
```
