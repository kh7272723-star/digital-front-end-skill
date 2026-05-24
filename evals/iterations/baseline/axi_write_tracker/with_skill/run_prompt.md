# Task Benchmark Run

- Task: `axi_write_tracker`
- Variant: `with_skill`
- Output file: `D:\skill管理\ic-design-skill\digital-front-end-skill-ds\evals\iterations\baseline\axi_write_tracker\with_skill\outputs\answer.md`

## Variant Instructions

Use the digital-front-end-skill at `D:\skill管理\ic-design-skill\digital-front-end-skill-ds\SKILL.md`.
Follow its workflow: contract -> state elements -> cycle trace -> RTL/checks for module tasks, or hierarchical workflow for large systems.

## User Prompt

Implement a bounded AXI full write burst tracker for a single-ID master slice. It should accept one command with AWLEN, hold AWVALID until AWREADY, emit W beats after AW acceptance, assert WLAST only on the final accepted beat, wait for B response before done, and report non-OKAY BRESP as error. Include contract, cycle trace, RTL, and checks.

## Save Requirement

Save final answer to `outputs/answer.md`. If RTL or testbench files are generated, save them under `outputs/` too.
