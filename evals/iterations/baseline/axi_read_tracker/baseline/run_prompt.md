# Task Benchmark Run

- Task: `axi_read_tracker`
- Variant: `baseline`
- Output file: `D:\skill管理\ic-design-skill\digital-front-end-skill-ds\evals\iterations\baseline\axi_read_tracker\baseline\outputs\answer.md`

## Variant Instructions

Do not use the digital-front-end-skill. Answer from general RTL knowledge only. Do not inspect the skill references.

## User Prompt

Implement a bounded AXI full read burst tracker for a single-ID master slice. It should accept one command with ARLEN, hold ARVALID until ARREADY, accept R beats after AR acceptance, check RLAST alignment, capture non-OKAY RRESP as error, and assert done only after the final expected accepted R beat. Include contract, cycle trace, RTL, and checks.

## Save Requirement

Save final answer to `outputs/answer.md`. If RTL or testbench files are generated, save them under `outputs/` too.
