# DMA burst planner trial

## Source basis

- Protocol rules: Arm AMBA AXI burst command fields and response-counting semantics.
- Open-source implementation style reviewed for inspiration, not copied:
  - alexforencich `verilog-axi` DMA modules: descriptor-driven AXI command generation and burst splitting.
  - PULP `axi`: modular AXI components and verification-oriented slicing.

## Slice goal

Convert one simple DMA descriptor into paired read/write burst commands:

- 32-bit data bus, 4 bytes per beat.
- Maximum burst length: 4 beats.
- Source and destination addresses must be 4-byte aligned.
- Byte count must be nonzero and a multiple of 4.
- Only full-width INCR-style beats are modeled.
- Read and write command counts must match.
- Expected B response count equals write command count.

This is not a full DMA. It does not include read data buffering, write data movement, error drain, abort, scatter-gather, or unaligned support.

## Contract

- `desc_valid_i && desc_ready_o` accepts one descriptor.
- Invalid descriptors produce `done_valid_o` with `error_o=1` and emit no commands.
- Valid descriptors emit paired read and write commands.
- Command payloads hold while the corresponding ready is low.
- `cmd_len_o` uses AXI encoding: beats minus one.
- `expected_b_count_o` reports the number of write commands emitted for the descriptor.
- `done_valid_o` asserts after the final write command is accepted.

## Verification matrix

| Scenario | Stimulus | Expected result | Checker | Priority |
| --- | --- | --- | --- | --- |
| 40-byte descriptor | 10 beats | burst lengths 3, 3, 1 | ordered checks | high |
| command backpressure | hold read/write ready low | command payload stable | direct checks | high |
| B response count | same descriptor | expected count = 3 | direct check | high |
| zero length | byte count zero | error done, no command | direct check | high |
| unaligned address | low address bits nonzero | error done, no command | direct check | high |

## Run

```text
python scripts/rtl_check.py --case evals/trials/dma_burst_planner_trial
```
