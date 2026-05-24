# Task Benchmark Run

- Task: `axi_lite_reg_block`
- Variant: `with_skill`
- Output file: `D:\skill管理\ic-design-skill\digital-front-end-skill-ds\evals\iterations\baseline\axi_lite_reg_block\with_skill\outputs\answer.md`

## Variant Instructions

Use the digital-front-end-skill at `D:\skill管理\ic-design-skill\digital-front-end-skill-ds\SKILL.md`.
Follow its workflow: contract -> state elements -> cycle trace -> RTL/checks for module tasks, or hierarchical workflow for large systems.

## User Prompt

Design an AXI-Lite register block with two 32-bit registers. The write address and write data channels can arrive in either order, B and R responses must hold under backpressure, and byte strobes must be honored. Use the skill workflow.

## Save Requirement

Save final answer to `outputs/answer.md`. If RTL or testbench files are generated, save them under `outputs/` too.
