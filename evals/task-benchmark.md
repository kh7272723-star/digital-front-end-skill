# Task Benchmark

This benchmark measures whether the skill makes an RTL agent behave more like an experienced engineer on realistic front-end tasks.

It is separate from `evals/evals.json`:

- `evals/evals.json` defines broad prompt coverage.
- `evals/task_benchmark.json` selects 12 engineer-level tasks and adds deterministic grading assertions.
- `scripts/init_task_benchmark.py` creates run directories.
- `scripts/grade_task_benchmark.py` grades saved outputs and writes `benchmark.json` plus `benchmark.md`.

## Workflow

Initialize an iteration:

```powershell
python .\scripts\init_task_benchmark.py --iteration 1
```

For each task directory, place agent outputs here:

```text
../digital-front-end-skill-workspace/iteration-1/<task>/with_skill/outputs/answer.md
../digital-front-end-skill-workspace/iteration-1/<task>/baseline/outputs/answer.md
```

Recommended run policy:

- `with_skill`: run the prompt with `digital-front-end-skill` explicitly loaded.
- `baseline`: run the same prompt without the skill, or with the previous skill snapshot if comparing revisions.
- Keep prompts unchanged between variants.
- Save final answer and any generated RTL/testbench files in `outputs/`.

Grade the iteration:

```powershell
python .\scripts\grade_task_benchmark.py --iteration-dir ..\digital-front-end-skill-workspace\iteration-1
```

Inspect:

```text
../digital-front-end-skill-workspace/iteration-1/benchmark.md
../digital-front-end-skill-workspace/iteration-1/benchmark.json
```

## What It Checks

The first task set emphasizes:

- contract before RTL
- state elements before RTL
- pre-edge / next-visible timing language
- Verilog naming discipline
- ready/valid, FIFO, pipeline, FSM behavior
- AXI-Lite and AXI full channel discipline
- DMA slice scoping and completion ordering
- CDC refusal for unsafe multi-bit crossings
- hierarchy instead of guessed monolithic AXI DMA RTL
- specialized patterns: retry buffer and width converter

The grader is intentionally mechanical. It does not prove RTL correctness. It catches missing engineering structure and obvious skill-regression signals before human review.

## Prompt Runner

Prepare all run prompts without executing an agent:

```powershell
python .\scripts\run_task_benchmark.py --iteration-dir ..\digital-front-end-skill-workspace\iteration-1
```

This writes `run_prompt.md` beside each `outputs/` directory.

Run a single task with an external agent command:

```powershell
python .\scripts\run_task_benchmark.py `
  --iteration-dir ..\digital-front-end-skill-workspace\iteration-1 `
  --task-id rv_register_slice `
  --variant with_skill `
  --agent-cmd "<your command reading {prompt_file} and writing {output_file}>"
```

Supported command placeholders:

- `{prompt_file}`
- `{output_file}`
- `{variant}`
- `{task_id}`
- `{skill_path}`
- `{root}`

If no agent command is available, fill each `outputs/answer.md` manually or from another model, then run the grader.
