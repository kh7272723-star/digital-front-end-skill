# Task Benchmark Run

- Task: `dma_burst_planner`
- Variant: `with_skill`
- Output file: `D:\skill管理\ic-design-skill\digital-front-end-skill-ds\evals\iterations\baseline\dma_burst_planner\with_skill\outputs\answer.md`

## Variant Instructions

Use the digital-front-end-skill at `D:\skill管理\ic-design-skill\digital-front-end-skill-ds\SKILL.md`.
Follow its workflow: contract -> state elements -> cycle trace -> RTL/checks for module tasks, or hierarchical workflow for large systems.

## User Prompt

Implement the first executable AXI DMA descriptor-to-burst planning slice. Scope it to aligned descriptors, full-width INCR-style beats, max four beats per burst, paired read/write command generation, and expected B response count. Include contract, cycle trace, RTL, and checks.

## Save Requirement

Save final answer to `outputs/answer.md`. If RTL or testbench files are generated, save them under `outputs/` too.
