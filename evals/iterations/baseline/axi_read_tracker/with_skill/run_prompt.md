# Task Benchmark Run

- Task: `axi_read_tracker`
- Variant: `with_skill`
- Output file: `D:\skill管理\ic-design-skill\digital-front-end-skill-ds\evals\iterations\baseline\axi_read_tracker\with_skill\outputs\answer.md`

## Variant Instructions

Use the digital-front-end-skill at `D:\skill管理\ic-design-skill\digital-front-end-skill-ds\SKILL.md`.
Follow its workflow: contract -> state elements -> cycle trace -> RTL/checks for module tasks, or hierarchical workflow for large systems.

## User Prompt

Implement a bounded AXI full read burst tracker for a single-ID master slice. It should accept one command with ARLEN, hold ARVALID until ARREADY, accept R beats after AR acceptance, check RLAST alignment, capture non-OKAY RRESP as error, and assert done only after the final expected accepted R beat. Include contract, cycle trace, RTL, and checks.

## Save Requirement

Save final answer to `outputs/answer.md`. If RTL or testbench files are generated, save them under `outputs/` too.
