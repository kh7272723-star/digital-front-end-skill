# Sub-Agent Delegation Rules

When delegating RTL work to sub-agents (parallel module generation, testbench writing, etc.), the sub-agent does not automatically load this skill. Without explicit rules, the sub-agent falls back to its training data — which produces the exact anti-patterns this skill exists to prevent (single-process FSMs, multi-bit values in FSM combinational blocks, mixed AW/W/B channels, wrong naming conventions).

## Rule

When spawning a sub-agent for RTL tasks, the prompt must include one of:

1. **Skill loading directive:** Tell the sub-agent to load this skill first (e.g., "Before writing any code, read and follow the rules in `<path>/SKILL.md` and the references it points to").

2. **Inline critical rules:** If the sub-agent cannot load the skill, include the key constraints directly in the prompt. At minimum, these rules must be present:
   - Two-process FSM style (state register in `always @(posedge clk)`, next-state + outputs in `always @(*)`)
   - Single-bit control rule: FSM combinational block assigns only single-bit enables and `state_d`. Multi-bit registers (addr, counter, len, data, wstrb) updated in synchronous blocks gated by those enables
   - Naming: `*_i`/`*_o` ports, `*_q`/`*_d` registered state, `wr_do`/`rd_do` for FIFO ops
   - AXI channel separation: AW/W/B independent valid/ready, RD/WR command paths independent
   - No `always @(*)` block computing multi-bit `_d` values gated on state (the "shadow datapath" anti-pattern)

3. **Post-generation review:** After the sub-agent delivers RTL, run the self-review checklist (Step 8) against its output before accepting it. Fix violations before integrating.

## Prompt Template

```
You are writing RTL for module `<module_name>`. Before writing code:
1. Read `<skill_path>/SKILL.md` and follow its workflow.
2. Read the interface contract at `<contract_path>` — pay special attention to port widths, signal semantics, and inter-module handshake rules.
3. Read the relevant pattern reference from `references/rtl/` or `references/axi-dma/`.
4. Read `references/debug/bug-pattern-library.md` SM1, SM2 for the single-bit control rule.
5. After writing RTL, self-review against the checklist in SKILL.md step 8.
6. Verify that your module's port widths and signal semantics MATCH the interface contract exactly.
```

## Critical Additions for Multi-Module Projects

- Sub-agents MUST read the interface contract file — not just the skill
- Port widths must be derived from the SAME parameters as the driving module
- Byte-to-beats conversions must use the ceiling division formula, not bit extraction
- Document whether `cmd_len_i` (or similar) is in bytes or beats — ambiguity causes integration bugs

## Expected Output Formats

**Design request:** Assumptions → Design contract → State elements → Cycle trace → RTL → Verification notes → Risks/corner cases → Review status.

**Review/debug request:** Observed evidence → Likely contract violation → Minimal fix → What to recheck → Residual uncertainty.

**Subsystem/full system:** Assumptions → System contract → Submodule decomposition → Interface contracts → Integration invariants → Local cycle traces → Implementation sequence → Verification strategy → Residual risks.
