#!/usr/bin/env python3
"""Static checks for the digital-front-end-skill package."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


BANNED_PATTERNS = [
    re.compile(r"\bin_fire\b"),
    re.compile(r"\bout_fire\b"),
    re.compile(r"\bfire\b"),
    re.compile(r"\bpush\b"),
    re.compile(r"\bpop\b"),
]


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def check_skill_lines(root: Path, errors: list[str]) -> None:
    skill = root / "SKILL.md"
    lines = read_text(skill).splitlines()
    if len(lines) > 500:
        errors.append(f"SKILL.md has {len(lines)} lines; expected <= 500")


def check_evals(root: Path, errors: list[str]) -> None:
    evals_path = root / "evals" / "evals.json"
    with evals_path.open("r", encoding="utf-8") as f:
        data = json.load(f)
    if data.get("skill_name") != "digital-front-end-skill":
        errors.append("evals.json skill_name mismatch")
    if not data.get("evals"):
        errors.append("evals.json has no evals")


def check_references_listed(root: Path, errors: list[str]) -> None:
    skill_text = read_text(root / "SKILL.md")
    for ref in sorted((root / "references").glob("*.md")):
        token = f"references/{ref.name}"
        if token not in skill_text:
            errors.append(f"Reference not listed in SKILL.md: {token}")


def check_banned_terms(root: Path, errors: list[str]) -> None:
    paths = [root / "SKILL.md", root / "evals" / "evals.json"]
    paths.extend(sorted((root / "references").glob("*.md")))
    for path in paths:
        text = read_text(path)
        for pattern in BANNED_PATTERNS:
            match = pattern.search(text)
            if match:
                errors.append(f"Banned term '{match.group(0)}' in {path.relative_to(root)}")


def check_fixtures(root: Path, errors: list[str]) -> None:
    fixture_root = root / "evals" / "fixtures"
    if not fixture_root.exists():
        errors.append("Missing evals/fixtures")
        return
    for case in sorted(p for p in fixture_root.iterdir() if p.is_dir()):
        manifest_path = case / "manifest.json"
        if not manifest_path.exists():
            errors.append(f"Missing manifest: {case.relative_to(root)}")
            continue
        with manifest_path.open("r", encoding="utf-8") as f:
            manifest = json.load(f)
        for field in ["name", "top", "sources", "testbench", "expected", "timeout_seconds"]:
            if field not in manifest:
                errors.append(f"{manifest_path.relative_to(root)} missing field {field}")
        for src in manifest.get("sources", []):
            if not (case / src).exists():
                errors.append(f"{case.relative_to(root)} missing source {src}")
        tb = manifest.get("testbench")
        if tb and not (case / tb).exists():
            errors.append(f"{case.relative_to(root)} missing testbench {tb}")


def check_benchmark(root: Path, errors: list[str]) -> None:
    benchmark_path = root / "evals" / "benchmark.json"
    if not benchmark_path.exists():
        errors.append("Missing evals/benchmark.json")
        return

    with (root / "evals" / "evals.json").open("r", encoding="utf-8") as f:
        evals_data = json.load(f)
    with benchmark_path.open("r", encoding="utf-8") as f:
        benchmark = json.load(f)

    eval_ids = {item.get("id") for item in evals_data.get("evals", [])}
    if len(evals_data.get("evals", [])) < int(benchmark.get("minimum_eval_count", 0)):
        errors.append("eval count is below benchmark minimum")

    for dimension in benchmark.get("dimensions", []):
        for eval_id in dimension.get("eval_ids", []):
            if eval_id not in eval_ids:
                errors.append(f"benchmark dimension {dimension.get('name')} references missing eval {eval_id}")

    for source in benchmark.get("official_protocol_sources", []):
        for ref in source.get("reference_files", []):
            if not (root / ref).exists():
                errors.append(f"benchmark protocol source missing reference {ref}")

    for trial in benchmark.get("executable_trials", []):
        if not (root / trial / "manifest.json").exists():
            errors.append(f"benchmark executable trial missing manifest {trial}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Run static checks for the skill package.")
    parser.add_argument("--root", default=".", help="Skill root directory.")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    errors: list[str] = []

    check_skill_lines(root, errors)
    check_evals(root, errors)
    check_references_listed(root, errors)
    check_banned_terms(root, errors)
    check_fixtures(root, errors)
    check_benchmark(root, errors)

    if errors:
        print("SKILL_STATIC_CHECK: FAIL")
        for error in errors:
            print(f"- {error}")
        return 1

    print("SKILL_STATIC_CHECK: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
