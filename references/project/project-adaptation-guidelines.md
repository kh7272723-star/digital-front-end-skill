# Project adaptation guidelines

## Purpose

Experienced RTL work starts by matching the local project.
Use this file when working in an existing repository or when the user provides local style, lint, reset, memory, or verification rules.

## What to inspect first

- Existing modules with similar interfaces.
- Naming conventions for clocks, resets, valid/ready, memories, and state.
- Reset polarity and synchrony.
- FSM style and state encoding.
- FIFO, RAM, and register slice examples already used in the project.
- Lint waiver style and common warnings.
- Testbench framework and pass/fail convention.

## Adaptation rules

- Project-local rules override this skill when they do not create a correctness issue.
- If local style conflicts with this skill, state the conflict and follow the local style for integration.
- Do not reformat unrelated code.
- Preserve existing module boundaries unless the requested fix requires a boundary change.
- Use the existing testbench/check style when extending tests.

## Output expectation

When adapting to a project, include:

- local conventions observed,
- conventions reused,
- any conflicts or risks,
- exact files or modules used as style examples,
- checks needed to confirm integration.
