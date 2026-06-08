#!/usr/bin/env python3
"""Artifact budget gate for RTL skill deliveries.

This gate keeps final project output reviewable. It rejects non-canonical
delivery artifacts that inflate context or make evidence ambiguous:

  - tb_archive/ with files
  - sim/*.vvp build products
  - duplicate simulation logs such as sim_addr_chan.log and sim_tb_addr_chan.log
  - project-local scripts/run_sim.py instead of the skill wrapper

Usage:
    python scripts/artifact_budget_gate.py <project_dir>
"""

from __future__ import annotations

import argparse
import io
import os
from pathlib import Path
import re
import sys


try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except (AttributeError, io.UnsupportedOperation):
    try:
        sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
        sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")
    except AttributeError:
        pass


def _rel(path: Path, project: Path) -> str:
    try:
        return str(path.relative_to(project)).replace("\\", "/")
    except ValueError:
        return str(path).replace("\\", "/")


def _read_text(path: Path) -> str:
    if not path.exists() or not path.is_file():
        return ""
    return path.read_text(encoding="utf-8", errors="replace")


def _has_explicit_waiver(project: Path, token: str) -> bool:
    """Return True only for an accepted limitation naming the token."""
    texts = []
    for rel in (
        "docs/dev_log.md",
        "docs/verification_evidence.md",
        "docs/verification_matrix.md",
    ):
        texts.append(_read_text(project / rel))
    joined = "\n".join(texts)
    for line in joined.splitlines():
        if token.lower() not in line.lower():
            continue
        if re.search(r"\bAccepted\s+Limitation\b", line, re.IGNORECASE):
            if re.search(r"\b(reason|because|risk|waiver)\b", line, re.IGNORECASE):
                return True
    return False


def _canonical_log_key(name: str) -> str:
    stem = Path(name).stem.lower()
    if stem.startswith("sim_"):
        stem = stem[4:]
    if stem.startswith("tb_"):
        stem = stem[3:]
    return stem


def check_artifact_budget(project: Path) -> list[str]:
    findings: list[str] = []

    tb_archive = project / "tb_archive"
    if tb_archive.exists():
        archived = [p for p in tb_archive.rglob("*") if p.is_file()]
        if archived:
            findings.append(
                f"Non-canonical delivery artifact: tb_archive/ contains "
                f"{len(archived)} file(s). Keep only canonical tb/ sources "
                "or document an Accepted Limitation before final PASS.")

    sim_dir = project / "sim"
    if sim_dir.exists():
        vvp_files = sorted(p for p in sim_dir.glob("*.vvp") if p.is_file())
        if vvp_files:
            shown = ", ".join(_rel(p, project) for p in vvp_files[:4])
            if len(vvp_files) > 4:
                shown += ", ..."
            findings.append(
                f"Build products in delivery: {shown}. Do not deliver .vvp "
                "files as evidence; keep guarded .log files instead.")

        logs_by_key: dict[str, list[Path]] = {}
        for log_path in sorted(sim_dir.glob("*.log")):
            logs_by_key.setdefault(_canonical_log_key(log_path.name), []).append(log_path)
        for key, paths in sorted(logs_by_key.items()):
            if len(paths) <= 1:
                continue
            names = [p.name.lower() for p in paths]
            has_sim = any(n.startswith("sim_") for n in names)
            has_sim_tb = any(n.startswith("sim_tb_") for n in names)
            if has_sim and has_sim_tb:
                shown = ", ".join(_rel(p, project) for p in paths)
                findings.append(
                    f"Duplicate simulation evidence for '{key}': {shown}. "
                    "Keep one canonical guarded log to avoid contradictory evidence.")

    local_run_sim = project / "scripts" / "run_sim.py"
    if local_run_sim.exists() and not _has_explicit_waiver(project, "run_sim.py"):
        findings.append(
            "Project-local scripts/run_sim.py found. Use the skill-provided "
            "scripts/run_sim_guarded.py command in logs, or document an "
            "Accepted Limitation with reason/risk before final PASS.")

    return findings


def main() -> None:
    parser = argparse.ArgumentParser(description="Reject non-canonical final artifacts.")
    parser.add_argument("project_dir", help="Project directory to check")
    args = parser.parse_args()

    project = Path(args.project_dir)
    if not project.is_dir():
        print(f"[REJECT] Not a directory: {project}", file=sys.stderr)
        sys.exit(1)

    findings = check_artifact_budget(project)
    if findings:
        print("ARTIFACT_BUDGET_GATE: FAIL")
        for finding in findings:
            print(f"  - {finding}")
        sys.exit(1)

    print("ARTIFACT_BUDGET_GATE: PASS")
    print("NEXT_WORKFLOW_STEP: continue through scripts/workflow_gate.py; standalone gate output is not phase evidence")
    sys.exit(0)


if __name__ == "__main__":
    main()
