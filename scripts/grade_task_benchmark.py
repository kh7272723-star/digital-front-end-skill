#!/usr/bin/env python3
"""Grade engineer-level task benchmark outputs with deterministic assertions."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


TEXT_SUFFIXES = {".md", ".txt", ".v", ".sv", ".vh", ".svh", ".json"}


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def write_json(path: Path, data: dict) -> None:
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def collect_output_text(output_dir: Path) -> tuple[str, list[str]]:
    if not output_dir.exists():
        return "", []

    chunks: list[str] = []
    files: list[str] = []
    for path in sorted(output_dir.rglob("*")):
        if not path.is_file() or path.suffix.lower() not in TEXT_SUFFIXES:
            continue
        rel = path.relative_to(output_dir).as_posix()
        files.append(rel)
        text = path.read_text(encoding="utf-8", errors="replace")
        chunks.append(f"\n\n## FILE: {rel}\n{text}")
    return "\n".join(chunks), files


def find_pattern(text: str, pattern: str) -> re.Match[str] | None:
    return re.search(pattern, text, flags=re.IGNORECASE | re.MULTILINE | re.DOTALL)


def evidence_for(text: str, pattern: str) -> str:
    match = find_pattern(text, pattern)
    if not match:
        return f"missing pattern: {pattern}"
    start = max(0, match.start() - 60)
    end = min(len(text), match.end() + 60)
    return text[start:end].replace("\n", " ").strip()


def grade_assertion(text: str, assertion: dict) -> tuple[bool, str]:
    kind = assertion["type"]
    if kind == "contains":
        pattern = assertion["pattern"]
        passed = find_pattern(text, pattern) is not None
        return passed, evidence_for(text, pattern)

    if kind == "absent":
        pattern = assertion["pattern"]
        match = find_pattern(text, pattern)
        if match:
            return False, evidence_for(text, pattern)
        return True, f"absent as required: {pattern}"

    if kind == "all_contains":
        missing = [p for p in assertion["patterns"] if find_pattern(text, p) is None]
        if missing:
            return False, "missing patterns: " + ", ".join(missing)
        return True, "all required patterns found"

    if kind == "any_contains":
        for pattern in assertion["patterns"]:
            if find_pattern(text, pattern):
                return True, evidence_for(text, pattern)
        return False, "none found: " + ", ".join(assertion["patterns"])

    if kind == "ordered":
        pos = -1
        found: list[str] = []
        for pattern in assertion["patterns"]:
            match = re.search(
                pattern,
                text[pos + 1 :],
                flags=re.IGNORECASE | re.MULTILINE | re.DOTALL,
            )
            if not match:
                return False, "ordered pattern missing after previous: " + pattern
            pos = pos + 1 + match.start()
            found.append(pattern)
        return True, "ordered patterns found: " + " -> ".join(found)

    return False, f"unknown assertion type: {kind}"


def main() -> int:
    parser = argparse.ArgumentParser(description="Grade task benchmark output directories.")
    parser.add_argument("--root", default=".", help="Skill root directory.")
    parser.add_argument("--iteration-dir", required=True, help="Benchmark iteration directory.")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    iteration_dir = Path(args.iteration_dir).resolve()
    task_benchmark = load_json(root / "evals" / "task_benchmark.json")
    variants = task_benchmark.get("variants", ["with_skill", "baseline"])
    summary: dict[str, dict[str, float | int]] = {}
    per_run: list[dict] = []

    for variant in variants:
        summary[variant] = {"passed": 0, "total": 0, "runs": 0}

    for task in task_benchmark["tasks"]:
        for variant in variants:
            run_dir = iteration_dir / task["id"] / variant
            output_text, files = collect_output_text(run_dir / "outputs")
            expectations = []
            pass_count = 0
            total = len(task["assertions"])

            if not files:
                expectations.append(
                    {
                        "text": "Output files exist.",
                        "passed": False,
                        "evidence": "No text output files found under outputs/.",
                    }
                )
            for assertion in task["assertions"]:
                passed, evidence = grade_assertion(output_text, assertion) if files else (False, "No output.")
                if passed:
                    pass_count += 1
                expectations.append(
                    {
                        "text": assertion["text"],
                        "passed": passed,
                        "evidence": evidence,
                    }
                )

            score = pass_count / total if total else 0.0
            grading = {
                "run_id": f"{task['id']}-{variant}",
                "eval_name": task["id"],
                "variant": variant,
                "score": score,
                "passed_assertions": pass_count,
                "total_assertions": total,
                "files": files,
                "expectations": expectations,
            }
            run_dir.mkdir(parents=True, exist_ok=True)
            write_json(run_dir / "grading.json", grading)

            summary[variant]["passed"] += pass_count
            summary[variant]["total"] += total
            summary[variant]["runs"] += 1
            per_run.append(grading)

    benchmark = {
        "skill_name": "digital-front-end-skill",
        "benchmark_name": task_benchmark["benchmark_name"],
        "benchmark_version": task_benchmark["version"],
        "iteration_dir": str(iteration_dir),
        "summary": {
            variant: {
                "passed_assertions": int(data["passed"]),
                "total_assertions": int(data["total"]),
                "pass_rate": (data["passed"] / data["total"]) if data["total"] else 0.0,
                "runs": int(data["runs"]),
            }
            for variant, data in summary.items()
        },
        "runs": per_run,
    }
    write_json(iteration_dir / "benchmark.json", benchmark)

    lines = ["# Task Benchmark Summary", ""]
    for variant, data in benchmark["summary"].items():
        lines.append(
            f"- {variant}: {data['passed_assertions']}/{data['total_assertions']} "
            f"assertions, pass_rate={data['pass_rate']:.3f}, runs={data['runs']}"
        )
    lines.append("")
    lines.append("## Per Run")
    for run in per_run:
        lines.append(
            f"- {run['run_id']}: {run['passed_assertions']}/"
            f"{run['total_assertions']} ({run['score']:.3f})"
        )
    (iteration_dir / "benchmark.md").write_text("\n".join(lines) + "\n", encoding="utf-8")

    print("TASK_BENCHMARK_GRADE: PASS")
    for variant, data in benchmark["summary"].items():
        print(
            f"{variant}: {data['passed_assertions']}/"
            f"{data['total_assertions']} pass_rate={data['pass_rate']:.3f}"
        )
    print(f"REPORT: {iteration_dir / 'benchmark.md'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
