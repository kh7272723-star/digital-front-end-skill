# Module Function Dictionary Template

For L2 multi-module projects, produce a structured function dictionary for each
sub-module. Save each as `docs/module-<name>-func-dict.md`.

## Purpose

- Extracts inputs/outputs/functionality/error-conditions from the spec
- Serves as the canonical spec reference during RTL generation (Step 7/7a)
- Prevents information loss between spec reading and RTL writing
- Each func-dict must cite specific source lines from the project spec

## Template

```markdown
# Module Function Dictionary: <module_name>

| Field | Value |
|-------|-------|
| Module Name | <name> |
| Parent System | <system> |
| Spec Source | <section/line refs from original spec> |
| Purpose | <one-sentence functional purpose> |

## Interface

### Inputs
| Signal | Width | Dir | Description |
|--------|-------|-----|-------------|
| clk | 1 | in | System clock |
| rst_n | 1 | in | Async reset, active low |
| ... | | | |

### Outputs
| Signal | Width | Dir | Description |
|--------|-------|-----|-------------|
| ... | | | |

## Functionality

<paragraph describing what this module does, in behavioral terms>

## Timing Contract

- Reference: docs/timing-contract.md#<section>
- Key constraints: <list>

## Error Conditions

| Condition | Response |
|-----------|----------|
| ... | ... |

## Dependencies

| Depends On | Interface |
|------------|-----------|
| ... | ... |

## Verification Notes

- Key scenarios to test: <list>
```

## Usage

- Create one func-dict per sub-module before any RTL is written
- Reference during Step 7/7a: "Use the module function dict as spec reference"
- Update if spec changes; func-dict is the canonical module-level spec
