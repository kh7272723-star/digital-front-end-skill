# Task Benchmark Run

- Task: `retry_buffer`
- Variant: `with_skill`
- Output file: `D:\skill管理\ic-design-skill\digital-front-end-skill-ds\evals\iterations\baseline\retry_buffer\with_skill\outputs\answer.md`

## Variant Instructions

Use the digital-front-end-skill at `D:\skill管理\ic-design-skill\digital-front-end-skill-ds\SKILL.md`.
Follow its workflow: contract -> state elements -> cycle trace -> RTL/checks for module tasks, or hierarchical workflow for large systems.

## User Prompt

Design a bounded retry buffer for a ready/valid packet stream with ACK/NAK replay. It must hold unacknowledged data, replay from the oldest unacknowledged item on NAK, and bound the in-flight window. Include contract, state elements, RTL outline, and verification checks.

## Save Requirement

Save final answer to `outputs/answer.md`. If RTL or testbench files are generated, save them under `outputs/` too.
