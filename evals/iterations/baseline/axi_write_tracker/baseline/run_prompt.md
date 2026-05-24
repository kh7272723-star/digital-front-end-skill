# Task Benchmark Run

- Task: `axi_write_tracker`
- Variant: `baseline`
- Output file: `D:\skill管理\ic-design-skill\digital-front-end-skill-ds\evals\iterations\baseline\axi_write_tracker\baseline\outputs\answer.md`

## Variant Instructions

Do not use the digital-front-end-skill. Answer from general RTL knowledge only. Do not inspect the skill references.

## User Prompt

Implement a bounded AXI full write burst tracker for a single-ID master slice. It should accept one command with AWLEN, hold AWVALID until AWREADY, emit W beats after AW acceptance, assert WLAST only on the final accepted beat, wait for B response before done, and report non-OKAY BRESP as error. Include contract, cycle trace, RTL, and checks.

## Save Requirement

Save final answer to `outputs/answer.md`. If RTL or testbench files are generated, save them under `outputs/` too.
