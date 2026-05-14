# Large module guidance

## Purpose

Use this file for modules larger than roughly 200 lines, modules with many always blocks, or unfamiliar integrated RTL.
The goal is to avoid local edits that break behavior outside the visible snippet.

## Navigation workflow

1. Scan structure before details: parameters, ports, declarations, assigns, always blocks, and submodule instances.
2. Summarize the module structure: clock domains, reset style, FSMs, main datapaths, and protocol boundaries.
3. Build a dependency map for the signal or behavior being changed.
4. Identify the change seam: which state register, next-state block, output assign, or instance owns the behavior.
5. Check blast radius: every downstream signal or module affected by the change.
6. Edit minimally following `references/brownfield-guidance.md`.
7. Search every occurrence of modified signals before finalizing.

## Reading strategy

- Do not read a large file only linearly.
- First locate module declaration, state registers, main valid/ready assignments, and instantiations.
- For a specific bug, trace backward from the failing output to its drivers.
- If the change touches a signal used in unread blocks, read those blocks before editing.

## Output rule

For large modules, provide a structure summary and blast-radius note before the patch or review finding.
