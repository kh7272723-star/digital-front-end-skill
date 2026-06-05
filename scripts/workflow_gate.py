#!/usr/bin/env python3
"""Phase-local workflow gate wrapper for digital-front-end RTL projects.

This script does not replace the detailed gates. It gives agents a single
phase command so failures are caught before the workflow moves on.

State lock: on PASS, writes docs/workflow_state.json under the project dir.
Later phases require predecessor PASS stamps before they can run.

Usage:
    python scripts/workflow_gate.py --phase pre-rtl <project_dir>
    python scripts/workflow_gate.py --phase post-rtl <project_dir>
    python scripts/workflow_gate.py --phase pre-integration <project_dir>
    python scripts/workflow_gate.py --phase post-sim <project_dir>
    python scripts/workflow_gate.py --phase final <project_dir>
    python scripts/workflow_gate.py --phase <phase> --force <project_dir>
"""

from __future__ import annotations

import argparse
import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from datetime import datetime, timezone


try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except (AttributeError, io.UnsupportedOperation):
    try:
        sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
        sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")
    except AttributeError:
        pass


SCRIPT_DIR = Path(__file__).resolve().parent
PHASE_ORDER = ["pre-rtl", "post-rtl", "pre-integration", "post-sim", "final"]
SCHEMA_VERSION = 1


# ---------------------------------------------------------------------------
#  Subprocess helpers
# ---------------------------------------------------------------------------

def run_script(script_name: str, args: list[str]) -> tuple[int, str]:
    cmd = [sys.executable, str(SCRIPT_DIR / script_name)] + args
    env = os.environ.copy()
    env.setdefault("PYTHONIOENCODING", "utf-8")
    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        env=env,
    )
    output = result.stdout
    if result.stderr:
        output += "\n" + result.stderr
    return result.returncode, output


def print_block(title: str, rc: int, output: str) -> None:
    print(f"--- {title}: rc={rc} ---")
    if output.strip():
        print(output.rstrip())


# ---------------------------------------------------------------------------
#  Project analysis
# ---------------------------------------------------------------------------

def detect_level(project: Path) -> str:
    """Detect project complexity level from dev_log.md or directory structure."""
    texts = []
    for rel in ("docs/dev_log.md", "dev_log.md"):
        path = project / rel
        if path.exists():
            texts.append(path.read_text(encoding="utf-8", errors="replace"))
    joined = "\n".join(texts)
    if re.search(r"\bL2\b|Level:\s*L2|Classification.*L2", joined, re.IGNORECASE):
        return "L2"
    if re.search(r"\bL0\b|Level:\s*L0|Classification.*L0", joined, re.IGNORECASE):
        return "L0"
    # Artifact-based inference: >=3 RTL files = L2
    rtl_dir = project / "rtl"
    if rtl_dir.exists() and len(list(rtl_dir.glob("*.v"))) + len(list(rtl_dir.glob("*.sv"))) >= 3:
        return "L2"
    return "L1"


def _is_l2_or_higher(level: str) -> bool:
    """L2 or any future non-L0/L1 level counts as complex."""
    return level not in ("L0", "L1")


def has_integration_artifacts(project: Path) -> bool:
    """Check if the project has integration TB or sim artifacts."""
    sim_dir = project / "sim"
    if sim_dir.exists():
        for p in sim_dir.iterdir():
            if p.suffix in (".vvp", ".log") and re.match(r"tb_|top_", p.stem, re.IGNORECASE):
                return True
    tb_dir = project / "tb"
    if tb_dir.exists():
        for p in tb_dir.iterdir():
            if p.suffix in (".v", ".sv") and re.match(r"tb_.*top|top_", p.stem, re.IGNORECASE):
                return True
    return False


# ---------------------------------------------------------------------------
#  State file management
# ---------------------------------------------------------------------------

def state_file_path(project: Path) -> Path:
    return project / "docs" / "workflow_state.json"


def load_state(project: Path) -> dict:
    path = state_file_path(project)
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        if data.get("schema_version") == SCHEMA_VERSION:
            return data
    except (json.JSONDecodeError, KeyError):
        pass
    return {}


def save_state(project: Path, state: dict) -> None:
    docs_dir = project / "docs"
    docs_dir.mkdir(parents=True, exist_ok=True)
    path = state_file_path(project)
    path.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def stamp_phase(state: dict, phase: str, status: str, evidence: str, cmd: str) -> None:
    """Write a phase result into the state dict. Only PASS is authoritative."""
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    state.setdefault("phases", {})[phase] = {
        "status": status,
        "timestamp": ts,
        "command": cmd,
        "evidence": evidence[:200],
    }


# ---------------------------------------------------------------------------
#  Predecessor chain
# ---------------------------------------------------------------------------

REQUIRED_PREDECESSORS: dict[str, list[str]] = {
    "pre-rtl": [],
    "post-rtl": ["pre-rtl"],
    "pre-integration": ["post-rtl"],
    "post-sim": ["post-rtl", "pre-integration"],
    "final": ["pre-rtl", "post-rtl", "pre-integration", "post-sim"],
}


def filter_required_predecessors(phase: str, level: str, project: Path) -> list[str]:
    """Return only the predecessors that apply to this level and project state."""
    all_req = REQUIRED_PREDECESSORS.get(phase, [])
    result = []
    for pred in all_req:
        if pred == "pre-rtl":
            # L0: pre-rtl is recommended but not enforced
            if level == "L0":
                continue
            result.append(pred)
        elif pred == "pre-integration":
            # L2 final delivery must prove the pre-integration lock ran.
            # Post-sim only needs it once integration artifacts exist.
            if phase == "final" and _is_l2_or_higher(level):
                result.append(pred)
            elif _is_l2_or_higher(level) and has_integration_artifacts(project):
                result.append(pred)
        else:
            result.append(pred)
    return result


def check_predecessors(state: dict, phase: str, level: str, project: Path) -> list[str]:
    """Return list of missing predecessor phase names. Empty = all clear."""
    required = filter_required_predecessors(phase, level, project)
    phases_done = state.get("phases", {})
    missing = []
    for pred in required:
        entry = phases_done.get(pred)
        if not entry or entry.get("status") != "PASS":
            missing.append(pred)
    return missing


def next_required_command(missing: list[str], project_dir: str) -> str:
    """Return the NEXT_REQUIRED_COMMAND line for the earliest missing phase."""
    earliest = missing[0]
    return (
        f"NEXT_REQUIRED_COMMAND: python scripts/workflow_gate.py "
        f"--phase {earliest} {project_dir}"
    )


# ---------------------------------------------------------------------------
#  Discovery helpers
# ---------------------------------------------------------------------------

def discover_verilog(project: Path) -> list[str]:
    files: list[Path] = []
    for subdir in ("rtl", "tb"):
        root = project / subdir
        if root.exists():
            files.extend(sorted(root.glob("*.v")))
            files.extend(sorted(root.glob("*.sv")))
    sim_dir = project / "sim"
    if sim_dir.exists():
        files.extend(sorted(sim_dir.glob("tb_*.v")))
        files.extend(sorted(sim_dir.glob("tb_*.sv")))
    return [str(p) for p in files]


def discover_compile_logs(project: Path) -> list[str]:
    sim_dir = project / "sim"
    if not sim_dir.exists():
        return []
    logs = []
    for path in sorted(sim_dir.glob("*.log")):
        if re.search(r"compile|iverilog|build", path.name, re.IGNORECASE):
            logs.append(str(path))
    return logs


def discover_sim_logs(project: Path) -> list[str]:
    sim_dir = project / "sim"
    if not sim_dir.exists():
        return []
    logs = []
    for path in sorted(sim_dir.glob("*.log")):
        if not re.search(r"compile|iverilog|build", path.name, re.IGNORECASE):
            logs.append(str(path))
    return logs


# ---------------------------------------------------------------------------
#  Per-phase gate logic
# ---------------------------------------------------------------------------

def _check_contract_readiness(project: Path, level: str) -> list[str]:
    """Verify required contracts/plans exist and are non-empty before RTL.

    For L0: only dev_log.md required (handled by preflight).
    For L1: timing-contract.md, verification_matrix.md.
    For L2: interface-contracts.md, timing-contract.md, contract_implementation_matrix.md,
            protocol_claim_ledger.md, verification_matrix.md.
    """
    if level == 'L0':
        return []

    findings: list[str] = []
    docs_dir = project / "docs"

    required = ["timing-contract.md", "verification_matrix.md"]
    if level in ('L2', 'L3'):
        required.extend([
            "interface-contracts.md",
            "contract_implementation_matrix.md",
            "protocol_claim_ledger.md",
        ])

    for fname in required:
        fpath = docs_dir / fname
        if not fpath.exists():
            findings.append(f"pre-rtl: missing required contract doc: docs/{fname}")
        elif not fpath.read_text(encoding="utf-8", errors="replace").strip():
            findings.append(f"pre-rtl: contract doc is empty: docs/{fname}")

    return findings


def gate_pre_rtl(project: Path) -> list[str]:
    findings: list[str] = []

    # 1. Project skeleton / preflight check
    rc, out = run_script("project_preflight_gate.py", [str(project)])
    print_block("project_preflight_gate", rc, out)
    if rc != 0:
        findings.append("project_preflight_gate failed")

    # 2. Contract readiness: required docs exist and are non-empty
    level = detect_level(project)
    contract_findings = _check_contract_readiness(project, level)
    findings.extend(contract_findings)

    return findings


def gate_post_rtl(project: Path) -> list[str]:
    findings: list[str] = []
    files = discover_verilog(project)
    if not files:
        return ["no RTL/TB Verilog files found for post-rtl gate"]

    level = detect_level(project)
    rc, out = run_script("rtl_style_check.py", ["--level", level] + files)
    print_block("rtl_style_check", rc, out)
    if "[E]" in out:
        findings.append("rtl_style_check has E-level findings")

    compile_logs = discover_compile_logs(project)
    if not compile_logs:
        findings.append("no compile log found under sim/ for post-rtl gate")
    for log in compile_logs:
        rc, out = run_script("compile_log_gate.py", [log])
        print_block(f"compile_log_gate {log}", rc, out)
        if rc != 0:
            findings.append(f"compile_log_gate failed: {log}")
    return findings


def gate_pre_integration(project: Path) -> list[str]:
    rc, out = run_script("pre_integration_gate.py", [str(project)])
    print_block("pre_integration_gate", rc, out)
    return [] if rc == 0 else ["pre_integration_gate failed"]


def gate_post_sim(project: Path) -> list[str]:
    findings: list[str] = []
    logs = discover_sim_logs(project)
    if not logs:
        return ["no simulation log found under sim/ for post-sim gate"]
    for log in logs:
        rc, out = run_script("sim_log_gate.py", [log])
        print_block(f"sim_log_gate {log}", rc, out)
        if rc != 0:
            findings.append(f"sim_log_gate failed: {log}")

    # L2: re-confirm pre-integration evidence is complete
    level = detect_level(project)
    if level in ('L2', 'L3'):
        rc, out = run_script("pre_integration_gate.py", [str(project)])
        print_block("pre_integration_gate (L2 re-confirm)", rc, out)
        if rc != 0:
            findings.append("L2 pre-integration evidence incomplete at post-sim gate")

    return findings


def gate_final(project: Path) -> list[str]:
    rc, out = run_script("final_delivery_gate.py", [str(project)])
    print_block("final_delivery_gate", rc, out)
    return [] if rc == 0 else ["final_delivery_gate failed"]


PHASE_GATE_MAP = {
    "pre-rtl": gate_pre_rtl,
    "post-rtl": gate_post_rtl,
    "pre-integration": gate_pre_integration,
    "post-sim": gate_post_sim,
    "final": gate_final,
}


# ---------------------------------------------------------------------------
#  Evidence summary
# ---------------------------------------------------------------------------

def summarize_evidence(phase: str, findings: list[str]) -> str:
    """Build a concise evidence string for the state file."""
    if not findings:
        return f"{phase} gate: all checks passed"
    return f"{phase} gate: {len(findings)} finding(s) -- {'; '.join(findings[:3])}"


# ---------------------------------------------------------------------------
#  Main
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(description="Run a phase-local RTL workflow gate.")
    parser.add_argument(
        "--phase",
        required=True,
        choices=PHASE_ORDER,
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Skip predecessor check (for recovery). Still records PASS only if gate passes.",
    )
    parser.add_argument("project_dir")
    args = parser.parse_args()

    project = Path(args.project_dir).resolve()
    phase = args.phase

    if not project.exists():
        print("PHASE_WORKFLOW_GATE: FAIL")
        print(f"- project_dir does not exist: {project}")
        return 2

    # Load existing state and detect level
    state = load_state(project)
    level = detect_level(project)
    state["level"] = level
    state["schema_version"] = SCHEMA_VERSION

    # Predecessor check
    if not args.force:
        missing = check_predecessors(state, phase, level, project)
        if missing:
            print("PHASE_WORKFLOW_GATE: FAIL")
            print(f"- Predecessor phase(s) not passed: {', '.join(missing)}")
            print(f"- {next_required_command(missing, str(project))}")
            return 1

    # Run the phase gate
    gate_fn = PHASE_GATE_MAP[phase]
    findings = gate_fn(project)

    # Build command string for audit trail
    cmd_str = f"python scripts/workflow_gate.py --phase {phase} {project}"

    if findings:
        print("PHASE_WORKFLOW_GATE: FAIL")
        for finding in findings:
            print(f"- {finding}")
        stamp_phase(state, phase, "FAIL", summarize_evidence(phase, findings), cmd_str)
        save_state(project, state)
        return 1

    # PASS: stamp state
    stamp_phase(state, phase, "PASS", summarize_evidence(phase, findings), cmd_str)
    save_state(project, state)

    print("PHASE_WORKFLOW_GATE: PASS")
    print(f"- State saved to {state_file_path(project)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
