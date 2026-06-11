# Human Escalation Protocol

## When to Escalate

Escalate to human when:

- 4th iteration on the same module fails (coder+verifier loop)
- 4th iteration on the same simulation failure (simulation loop)
- Error source is "Unclear" after 2 classification attempts
  (error-source-tracing.md Category 4)
- A gate failure persists after 3 fix+recheck cycles
- The spec is internally contradictory or missing critical information
- A required tool is unavailable and no fallback exists

## Escalation Report Template

Every escalation MUST include ALL 5 fields below:

### Escalation Report

- **Trigger**: [Which condition was hit, with evidence]
- **What Was Attempted**: [Iterations tried, results of each]
- **Error Classification**: [Category 1/2/3/4 from error-source-tracing.md,
  with reasoning]
- **Current State**: [What works, what fails, what is partially working]
- **Question for Human**: [Single specific actionable question. NOT "what should
  I do?" but e.g. "The spec says X on line 47 but requires Y on line 89. Which
  takes priority?"]

## After Escalation

- Do NOT continue development until human responds
- Record the escalation in `docs/dev_log.md` with the report content
- When human responds, apply the decision and continue from where the
  escalation was raised
