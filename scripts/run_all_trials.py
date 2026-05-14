#!/usr/bin/env python3
"""Run all executable RTL trials listed in evals/benchmark.json."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def main() -> int:
    parser = argparse.ArgumentParser(description="Run all benchmark executable RTL trials.")
    parser.add_argument("--root", default=".", help="Skill root directory.")
    parser.add_argument(
        "--optional-tools",
        action="store_true",
        help="Ask rtl_check.py to run optional Verilator/Yosys checks when installed.",
    )
    args = parser.parse_args()

    root = Path(args.root).resolve()
    benchmark = load_json(root / "evals" / "benchmark.json")
    trials = benchmark.get("executable_trials", [])
    checker = root / "scripts" / "rtl_check.py"
    failures: list[str] = []

    print(f"TRIAL_COUNT: {len(trials)}")
    for trial in trials:
        cmd = [sys.executable, str(checker), "--case", str(root / trial)]
        if args.optional_tools:
            cmd.append("--optional-tools")
        proc = subprocess.run(
            cmd,
            cwd=str(root),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        status = "PASS" if proc.returncode == 0 else "FAIL"
        print(f"{status}: {trial}")
        if proc.returncode != 0:
            failures.append(trial)
            print(proc.stdout.rstrip())

    if failures:
        print("RUN_ALL_TRIALS: FAIL")
        for failure in failures:
            print(f"- {failure}")
        return 1

    print("RUN_ALL_TRIALS: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
