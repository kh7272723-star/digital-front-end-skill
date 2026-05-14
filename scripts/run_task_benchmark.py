#!/usr/bin/env python3
"""Prepare or run task benchmark prompts for with-skill/baseline variants."""

from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def render_run_prompt(
    *,
    task_id: str,
    variant: str,
    prompt: str,
    skill_path: Path,
    output_file: Path,
) -> str:
    if variant == "with_skill":
        variant_instructions = (
            f"Use the digital-front-end-skill at `{skill_path}`.\n"
            "Follow its workflow: contract -> state elements -> cycle trace -> RTL/checks "
            "for module tasks, or hierarchical workflow for large systems."
        )
    else:
        variant_instructions = (
            "Do not use the digital-front-end-skill. Answer from general RTL knowledge only. "
            "Do not inspect the skill references."
        )

    return (
        f"# Task Benchmark Run\n\n"
        f"- Task: `{task_id}`\n"
        f"- Variant: `{variant}`\n"
        f"- Output file: `{output_file}`\n\n"
        f"## Variant Instructions\n\n"
        f"{variant_instructions}\n\n"
        f"## User Prompt\n\n"
        f"{prompt}\n\n"
        f"## Save Requirement\n\n"
        f"Save final answer to `outputs/answer.md`. If RTL or testbench files are generated, "
        f"save them under `outputs/` too.\n"
    )


def apply_template(template: str, values: dict[str, str]) -> str:
    result = template
    for key, value in values.items():
        result = result.replace("{" + key + "}", value)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description="Prepare or run task benchmark variants.")
    parser.add_argument("--root", default=".", help="Skill root directory.")
    parser.add_argument("--iteration-dir", required=True, help="Benchmark iteration directory.")
    parser.add_argument(
        "--agent-cmd",
        default=None,
        help=(
            "Optional command template to execute one run. Placeholders: "
            "{prompt_file}, {output_file}, {variant}, {task_id}, {skill_path}, {root}"
        ),
    )
    parser.add_argument("--task-id", action="append", default=None, help="Run only this task id.")
    parser.add_argument("--variant", action="append", default=None, help="Run only this variant.")
    parser.add_argument("--force", action="store_true", help="Overwrite existing outputs.")
    parser.add_argument("--grade", action="store_true", help="Run grade_task_benchmark.py after runs.")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    iteration_dir = Path(args.iteration_dir).resolve()
    task_benchmark = load_json(root / "evals" / "task_benchmark.json")
    evals = load_json(root / "evals" / "evals.json").get("evals", [])
    eval_by_id = {item["id"]: item for item in evals}
    selected_tasks = set(args.task_id or [])
    selected_variants = set(args.variant or task_benchmark.get("variants", []))
    skill_path = root / "SKILL.md"

    prepared = 0
    executed = 0
    skipped = 0
    failed: list[str] = []

    for task in task_benchmark["tasks"]:
        task_id = task["id"]
        if selected_tasks and task_id not in selected_tasks:
            continue
        source = eval_by_id[task["source_eval_id"]]
        prompt = source["prompt"]

        for variant in task_benchmark.get("variants", ["with_skill", "baseline"]):
            if selected_variants and variant not in selected_variants:
                continue

            run_dir = iteration_dir / task_id / variant
            output_dir = run_dir / "outputs"
            output_dir.mkdir(parents=True, exist_ok=True)
            output_file = output_dir / "answer.md"
            prompt_file = run_dir / "run_prompt.md"
            prompt_text = render_run_prompt(
                task_id=task_id,
                variant=variant,
                prompt=prompt,
                skill_path=skill_path,
                output_file=output_file,
            )
            prompt_file.write_text(prompt_text, encoding="utf-8")
            prepared += 1

            if output_file.exists() and not args.force:
                skipped += 1
                continue

            if args.agent_cmd:
                command = apply_template(
                    args.agent_cmd,
                    {
                        "prompt_file": str(prompt_file),
                        "output_file": str(output_file),
                        "variant": variant,
                        "task_id": task_id,
                        "skill_path": str(skill_path),
                        "root": str(root),
                    },
                )
                proc = subprocess.run(
                    command,
                    cwd=str(root),
                    text=True,
                    shell=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    check=False,
                )
                (run_dir / "agent.log").write_text(proc.stdout, encoding="utf-8")
                if proc.returncode == 0 and output_file.exists():
                    executed += 1
                else:
                    failed.append(f"{task_id}/{variant}")

    if args.grade:
        subprocess.run(
            [
                "python",
                str(root / "scripts" / "grade_task_benchmark.py"),
                "--root",
                str(root),
                "--iteration-dir",
                str(iteration_dir),
            ],
            cwd=str(root),
            check=False,
        )

    print("TASK_BENCHMARK_RUNNER: PASS" if not failed else "TASK_BENCHMARK_RUNNER: FAIL")
    print(f"ITERATION_DIR: {iteration_dir}")
    print(f"PREPARED_PROMPTS: {prepared}")
    print(f"SKIPPED_EXISTING_OUTPUTS: {skipped}")
    print(f"EXECUTED_AGENT_RUNS: {executed}")
    if not args.agent_cmd:
        print("MODE: manual prompt preparation")
    if failed:
        print("FAILED_RUNS:")
        for item in failed:
            print(f"- {item}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
