#!/usr/bin/env python3
"""Initialize an engineer-level task benchmark workspace."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def write_json(path: Path, data: dict) -> None:
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Create task benchmark run directories.")
    parser.add_argument("--root", default=".", help="Skill root directory.")
    parser.add_argument(
        "--workspace",
        default=None,
        help="Workspace directory. Default: sibling digital-front-end-skill-workspace.",
    )
    parser.add_argument("--iteration", type=int, default=1, help="Iteration number.")
    parser.add_argument(
        "--variant",
        action="append",
        default=None,
        help="Variant to create. Defaults to variants listed in task_benchmark.json.",
    )
    args = parser.parse_args()

    root = Path(args.root).resolve()
    workspace = (
        Path(args.workspace).resolve()
        if args.workspace
        else root.parent / "digital-front-end-skill-workspace"
    )
    iteration_dir = workspace / f"iteration-{args.iteration}"
    task_benchmark = load_json(root / "evals" / "task_benchmark.json")
    evals = load_json(root / "evals" / "evals.json").get("evals", [])
    eval_by_id = {item["id"]: item for item in evals}
    variants = args.variant or task_benchmark.get("variants", ["with_skill", "baseline"])

    iteration_dir.mkdir(parents=True, exist_ok=True)
    write_json(
        iteration_dir / "benchmark_manifest.json",
        {
            "benchmark_name": task_benchmark["benchmark_name"],
            "benchmark_version": task_benchmark["version"],
            "skill_root": str(root),
            "created_at": datetime.now(timezone.utc).isoformat(),
            "variants": variants,
            "task_count": len(task_benchmark["tasks"]),
        },
    )

    for task in task_benchmark["tasks"]:
        source = eval_by_id.get(task["source_eval_id"])
        if source is None:
            raise KeyError(f"Missing source eval id {task['source_eval_id']}")

        task_dir = iteration_dir / task["id"]
        task_dir.mkdir(parents=True, exist_ok=True)
        prompt_text = source["prompt"]
        (task_dir / "prompt.md").write_text(prompt_text + "\n", encoding="utf-8")
        write_json(
            task_dir / "eval_metadata.json",
            {
                "eval_id": task["source_eval_id"],
                "eval_name": task["id"],
                "category": task["category"],
                "prompt": prompt_text,
                "expected_output": source.get("expected_output", ""),
                "assertions": [assertion["text"] for assertion in task["assertions"]],
            },
        )

        for variant in variants:
            run_dir = task_dir / variant
            output_dir = run_dir / "outputs"
            output_dir.mkdir(parents=True, exist_ok=True)
            instruction = (
                f"# {task['id']} / {variant}\n\n"
                "Put the agent output files in `outputs/`.\n"
                "Preferred file: `outputs/answer.md`.\n"
                "Then run:\n\n"
                "```powershell\n"
                f"python {root / 'scripts' / 'grade_task_benchmark.py'} "
                f"--iteration-dir {iteration_dir}\n"
                "```\n"
            )
            (run_dir / "RUN_INSTRUCTIONS.md").write_text(instruction, encoding="utf-8")

    print(f"TASK_BENCHMARK_INIT: PASS")
    print(f"ITERATION_DIR: {iteration_dir}")
    print(f"TASKS: {len(task_benchmark['tasks'])}")
    print(f"VARIANTS: {', '.join(variants)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
