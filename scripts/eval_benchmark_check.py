#!/usr/bin/env python3
"""Check benchmark coverage for the digital-front-end skill eval suite."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def main() -> int:
    parser = argparse.ArgumentParser(description="Check eval benchmark coverage.")
    parser.add_argument("--root", default=".", help="Skill root directory.")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    evals_path = root / "evals" / "evals.json"
    benchmark_path = root / "evals" / "benchmark.json"
    errors: list[str] = []

    evals_data = load_json(evals_path)
    benchmark = load_json(benchmark_path)

    evals = evals_data.get("evals", [])
    eval_ids = [item.get("id") for item in evals]
    eval_id_set = set(eval_ids)

    if len(eval_ids) != len(eval_id_set):
        errors.append("evals.json contains duplicate eval ids")

    minimum_eval_count = int(benchmark.get("minimum_eval_count", 0))
    if len(evals) < minimum_eval_count:
        errors.append(f"eval count {len(evals)} is below required {minimum_eval_count}")

    required_assertions = int(benchmark.get("required_assertions_per_eval", 0))
    for item in evals:
        if not item.get("prompt"):
            errors.append(f"eval {item.get('id')} missing prompt")
        if not item.get("expected_output"):
            errors.append(f"eval {item.get('id')} missing expected_output")
        if len(item.get("assertions", [])) < required_assertions:
            errors.append(
                f"eval {item.get('id')} has fewer than {required_assertions} assertions"
            )

    print("BENCHMARK_COVERAGE:")
    for dimension in benchmark.get("dimensions", []):
        name = dimension.get("name", "<unnamed>")
        ids = dimension.get("eval_ids", [])
        min_count = int(dimension.get("min_count", 0))
        missing = [eval_id for eval_id in ids if eval_id not in eval_id_set]
        if missing:
            errors.append(f"dimension {name} references missing eval ids {missing}")
        if len(ids) < min_count:
            errors.append(f"dimension {name} has {len(ids)} eval ids; expected >= {min_count}")
        print(f"- {name}: {len(ids)} evals, min {min_count}")

    for source in benchmark.get("official_protocol_sources", []):
        protocol = source.get("protocol", "<unknown>")
        if not source.get("owner") or not source.get("document"):
            errors.append(f"protocol source {protocol} missing owner or document")
        for ref in source.get("reference_files", []):
            if not (root / ref).exists():
                errors.append(f"protocol source {protocol} missing reference file {ref}")
        missing = [eval_id for eval_id in source.get("eval_ids", []) if eval_id not in eval_id_set]
        if missing:
            errors.append(f"protocol source {protocol} references missing eval ids {missing}")

    executable_trials = benchmark.get("executable_trials", [])
    if len(executable_trials) != len(set(executable_trials)):
        errors.append("benchmark.json contains duplicate executable trials")

    minimum_executable_trials = int(benchmark.get("minimum_executable_trials", 0))
    if len(executable_trials) < minimum_executable_trials:
        errors.append(
            f"executable trial count {len(executable_trials)} is below required "
            f"{minimum_executable_trials}"
        )

    required_manifest_fields = ["name", "top", "sources", "testbench", "expected", "timeout_seconds"]
    for trial in executable_trials:
        trial_path = root / trial
        manifest = trial_path / "manifest.json"
        if not manifest.exists():
            errors.append(f"missing executable trial manifest: {trial}")
            continue
        trial_manifest = load_json(manifest)
        for field in required_manifest_fields:
            if field not in trial_manifest:
                errors.append(f"trial {trial} manifest missing field {field}")
        if not isinstance(trial_manifest.get("sources", []), list):
            errors.append(f"trial {trial} sources must be a list")
        for source in trial_manifest.get("sources", []):
            if not (trial_path / source).exists():
                errors.append(f"trial {trial} missing source {source}")
        testbench = trial_manifest.get("testbench")
        if testbench and not (trial_path / testbench).exists():
            errors.append(f"trial {trial} missing testbench {testbench}")
        expected = trial_manifest.get("expected", {})
        if expected.get("result") not in ("pass", "fail"):
            errors.append(f"trial {trial} expected.result must be pass or fail")
        if not isinstance(expected.get("contains", []), list):
            errors.append(f"trial {trial} expected.contains must be a list")

    task_benchmark_file = benchmark.get("task_benchmark_file")
    if task_benchmark_file:
        task_benchmark_path = root / task_benchmark_file
        if not task_benchmark_path.exists():
            errors.append(f"missing task benchmark file: {task_benchmark_file}")
        else:
            task_benchmark = load_json(task_benchmark_path)
            tasks = task_benchmark.get("tasks", [])
            task_ids = [task.get("id") for task in tasks]
            if len(task_ids) != len(set(task_ids)):
                errors.append("task benchmark contains duplicate task ids")
            minimum_tasks = int(benchmark.get("minimum_task_benchmark_tasks", 0))
            if len(tasks) < minimum_tasks:
                errors.append(
                    f"task benchmark count {len(tasks)} is below required {minimum_tasks}"
                )
            minimum_assertions = int(
                benchmark.get("minimum_task_benchmark_assertions_per_task", 0)
            )
            for task in tasks:
                source_eval_id = task.get("source_eval_id")
                if source_eval_id not in eval_id_set:
                    errors.append(
                        f"task benchmark {task.get('id')} references missing eval id "
                        f"{source_eval_id}"
                    )
                assertions = task.get("assertions", [])
                if len(assertions) < minimum_assertions:
                    errors.append(
                        f"task benchmark {task.get('id')} has fewer than "
                        f"{minimum_assertions} assertions"
                    )
                for assertion in assertions:
                    assertion_type = assertion.get("type")
                    if assertion_type not in (
                        "contains",
                        "absent",
                        "all_contains",
                        "any_contains",
                        "ordered",
                    ):
                        errors.append(
                            f"task benchmark {task.get('id')} has unknown assertion "
                            f"type {assertion_type}"
                        )
                    if assertion_type in ("contains", "absent") and not assertion.get("pattern"):
                        errors.append(
                            f"task benchmark {task.get('id')} assertion missing pattern"
                        )
                    if assertion_type in ("all_contains", "any_contains", "ordered") and not assertion.get("patterns"):
                        errors.append(
                            f"task benchmark {task.get('id')} assertion missing patterns"
                        )

    if errors:
        print("EVAL_BENCHMARK_CHECK: FAIL")
        for error in errors:
            print(f"- {error}")
        return 1

    print(f"TOTAL_EVALS: {len(evals)}")
    print(f"EXECUTABLE_TRIALS: {len(executable_trials)}")
    if task_benchmark_file:
        print(f"TASK_BENCHMARK: {task_benchmark_file}")
    print("EVAL_BENCHMARK_CHECK: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
