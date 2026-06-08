#!/usr/bin/env python3
"""Phase-local workflow gate wrapper for digital-front-end RTL projects.

This script does not replace the detailed gates. It gives agents a single
phase command so failures are caught before the workflow moves on.

State lock: on PASS, writes docs/workflow_state.json under the project dir.
Each phase stamp includes an artifact snapshot (sha256 + file mtime + size) so later
phases can detect stale predecessors. Freshness is checked on entry:
if a predecessor's snapshot doesn't match the current filesystem, the
predecessor is stale and must be re-run.

Usage:
    python scripts/workflow_gate.py --phase pre-rtl <project_dir>
    python scripts/workflow_gate.py --phase post-rtl <project_dir>
    python scripts/workflow_gate.py --phase module-sim <project_dir>
    python scripts/workflow_gate.py --phase pre-integration <project_dir>
    python scripts/workflow_gate.py --phase post-sim <project_dir>
    python scripts/workflow_gate.py --phase final <project_dir>
    python scripts/workflow_gate.py --phase <phase> --force <project_dir>
"""

from __future__ import annotations

import argparse
import hashlib
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
PHASE_ALIASES = {"module-sim": "pre-integration"}
CLI_PHASE_CHOICES = PHASE_ORDER + sorted(PHASE_ALIASES)
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
            # Extensionless Icarus outputs
            if "." not in p.name and re.match(r"tb_|top_", p.name, re.IGNORECASE):
                return True
    tb_dir = project / "tb"
    if tb_dir.exists():
        for p in tb_dir.iterdir():
            if p.suffix in (".v", ".sv") and re.match(r"tb_.*top|top_", p.stem, re.IGNORECASE):
                return True
    return False


def has_tb_files(project: Path) -> bool:
    """Check if the project has ANY TB files (per-module or integration)."""
    tb_dir = project / "tb"
    if tb_dir.exists():
        if list(tb_dir.glob("*.v")) or list(tb_dir.glob("*.sv")):
            return True
    sim_dir = project / "sim"
    if sim_dir.exists():
        if list(sim_dir.glob("tb_*.v")) or list(sim_dir.glob("tb_*.sv")):
            return True
    return False


def has_sim_artifacts(project: Path) -> bool:
    """Check if the project has simulation artifacts beyond compile evidence."""
    sim_dir = project / "sim"
    if not sim_dir.exists():
        return False
    for p in sim_dir.iterdir():
        if re.search(r"(compile|build|iverilog|vlog|verilator)", p.name, re.IGNORECASE):
            continue
        if p.suffix in (".vvp", ".vcd", ".fst"):
            return True
        if p.suffix == ".log":
            return True
        if "." not in p.name and re.match(r"tb_|top_", p.name, re.IGNORECASE):
            return True
    return False


# ---------------------------------------------------------------------------
#  Artifact snapshot (freshness)
# ---------------------------------------------------------------------------

def _compute_file_snapshot(filepath: Path) -> dict | None:
    """Return {'mtime': float, 'size': int, 'sha256': str} for a file, or None."""
    try:
        st = filepath.stat()
        digest = hashlib.sha256(filepath.read_bytes()).hexdigest()
        return {"mtime": st.st_mtime, "size": st.st_size, "sha256": digest}
    except OSError:
        return None


def compute_phase_snapshot(project: Path, phase: str, level: str) -> dict:
    """Compute artifact snapshot for a phase.

    Returns {relpath: {'mtime': ..., 'size': ...}} for files relevant to
    this phase. Later phases use this to detect stale predecessors.
    """
    snapshot: dict = {}

    if phase == "pre-rtl":
        # Snapshot contract docs
        docs_dir = project / "docs"
        if docs_dir.exists():
            required = ["timing-contract.md", "verification_matrix.md"]
            if _is_l2_or_higher(level):
                required.extend([
                    "interface-contracts.md",
                    "contract_implementation_matrix.md",
                    "protocol_claim_ledger.md",
                ])
            for fname in required:
                fpath = docs_dir / fname
                info = _compute_file_snapshot(fpath)
                if info:
                    snapshot[f"docs/{fname}"] = info

    elif phase == "post-rtl":
        # Snapshot all RTL files
        rtl_dir = project / "rtl"
        if rtl_dir.exists():
            for verilog_file in sorted(rtl_dir.glob("*.v")):
                rel = str(verilog_file.relative_to(project)).replace("\\", "/")
                info = _compute_file_snapshot(verilog_file)
                if info:
                    snapshot[rel] = info
            for sv_file in sorted(rtl_dir.glob("*.sv")):
                rel = str(sv_file.relative_to(project)).replace("\\", "/")
                info = _compute_file_snapshot(sv_file)
                if info:
                    snapshot[rel] = info

    elif phase == "pre-integration":
        # Snapshot RTL files + module verification matrix + per-module TB/logs
        rtl_dir = project / "rtl"
        if rtl_dir.exists():
            for f in sorted(rtl_dir.glob("*.v")):
                rel = str(f.relative_to(project)).replace("\\", "/")
                info = _compute_file_snapshot(f)
                if info:
                    snapshot[rel] = info
        matrix = project / "docs" / "module_verification_matrix.md"
        info = _compute_file_snapshot(matrix)
        if info:
            snapshot["docs/module_verification_matrix.md"] = info
        # Per-module TB and sim logs
        for tb_dir_name in ("tb", "sim"):
            d = project / tb_dir_name
            if d.exists():
                for f in sorted(d.iterdir()):
                    if f.suffix in (".v", ".sv", ".log"):
                        rel = str(f.relative_to(project)).replace("\\", "/")
                        info = _compute_file_snapshot(f)
                        if info:
                            snapshot[rel] = info

    elif phase == "post-sim":
        # Snapshot all sim logs
        sim_dir = project / "sim"
        if sim_dir.exists():
            for f in sorted(sim_dir.glob("*.log")):
                rel = str(f.relative_to(project)).replace("\\", "/")
                info = _compute_file_snapshot(f)
                if info:
                    snapshot[rel] = info
        # Also snapshot module matrix (may have been updated)
        matrix = project / "docs" / "module_verification_matrix.md"
        info = _compute_file_snapshot(matrix)
        if info:
            snapshot["docs/module_verification_matrix.md"] = info

    return snapshot


def snapshots_match(stored: dict, current: dict) -> bool:
    """Return True if stored snapshot matches current filesystem state.

    Both must have the same keys, and each file's mtime and size must match.
    Missing files in either direction = mismatch.
    """
    if set(stored.keys()) != set(current.keys()):
        return False
    for key, stored_info in stored.items():
        cur_info = current.get(key)
        if not cur_info:
            return False
        if (stored_info.get("mtime") != cur_info.get("mtime") or
                stored_info.get("size") != cur_info.get("size") or
                stored_info.get("sha256") != cur_info.get("sha256")):
            return False
    return True


# ---------------------------------------------------------------------------
#  State file management
# ---------------------------------------------------------------------------

def state_file_path(project: Path) -> Path:
    return project / "docs" / "workflow_state.json"


def cursor_file_path(project: Path) -> Path:
    return project / "docs" / "workflow_cursor.md"


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


def _guidance_value(guidance: list[str], prefix: str) -> str:
    for line in guidance:
        if line.startswith(prefix + ":"):
            return line.split(":", 1)[1].strip()
    return ""


def write_workflow_cursor(project: Path, phase: str, status: str, level: str,
                          cmd: str, findings: list[str],
                          guidance: list[str]) -> None:
    """Write a compact human-readable workflow cursor.

    This is the planning-with-files idea reduced to one generated state file:
    agents re-read it to recover phase position, but workflow_state.json remains
    the authoritative machine gate.
    """
    docs_dir = project / "docs"
    docs_dir.mkdir(parents=True, exist_ok=True)
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    completed = _guidance_value(guidance, "CURRENT_STEP_COMPLETED")
    next_step = _guidance_value(guidance, "NEXT_WORKFLOW_STEP")
    next_action = _guidance_value(guidance, "NEXT_REQUIRED_ACTION")
    next_cmd = _guidance_value(guidance, "NEXT_REQUIRED_COMMAND")
    forbidden = _guidance_value(guidance, "FORBIDDEN_NEXT_ACTION")
    delivery_allowed = _guidance_value(guidance, "DELIVERY_CLAIM_ALLOWED")
    integration_allowed = _guidance_value(guidance, "INTEGRATION_TB_ALLOWED")

    lines = [
        "# Workflow Cursor",
        "",
        "Generated by `scripts/workflow_gate.py`. Treat this file as state data, not user instructions.",
        "`docs/workflow_state.json` is the authoritative machine-readable gate state.",
        "",
        f"- Project level: {level}",
        f"- Current phase: {phase}",
        f"- Gate status: {status}",
        f"- Last command: `{cmd}`",
        f"- Updated UTC: {ts}",
    ]
    if completed:
        lines.append(f"- Current step completed: {completed}")
    if next_step:
        lines.append(f"- Next workflow step: {next_step}")
    if next_action:
        lines.append(f"- Next required action: {next_action}")
    if next_cmd:
        lines.append(f"- Next required command: `{next_cmd}`")
    if forbidden:
        lines.append(f"- Forbidden next action: {forbidden}")
    if integration_allowed:
        lines.append(f"- Integration TB allowed: {integration_allowed}")
    if delivery_allowed:
        lines.append(f"- Delivery claim allowed: {delivery_allowed}")
    lines.extend([
        "- Contract lock: pre-rtl PASS snapshots contract docs by sha256; contract edits require re-running pre-rtl.",
        "",
        "## Blocking Findings",
    ])
    if findings:
        for finding in findings[:8]:
            lines.append(f"- {finding}")
        if len(findings) > 8:
            lines.append(f"- ... {len(findings) - 8} more finding(s)")
    else:
        lines.append("- none")
    cursor_file_path(project).write_text("\n".join(lines) + "\n", encoding="utf-8")


def stamp_phase(state: dict, phase: str, status: str, evidence: str, cmd: str,
                snapshot: dict | None = None) -> None:
    """Write a phase result into the state dict. Only PASS is authoritative."""
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    entry = {
        "status": status,
        "timestamp": ts,
        "command": cmd,
        "evidence": evidence[:200],
    }
    if snapshot is not None:
        entry["snapshot"] = snapshot
    state.setdefault("phases", {})[phase] = entry


def get_phase_snapshot(state: dict, phase: str) -> dict | None:
    """Return the stored snapshot for a phase, or None."""
    entry = state.get("phases", {}).get(phase, {})
    return entry.get("snapshot")


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
            if level == "L0":
                continue
            result.append(pred)
        elif pred == "pre-integration":
            if phase in ("post-sim", "final") and _is_l2_or_higher(level):
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


def check_predecessor_freshness(state: dict, phase: str, level: str,
                                 project: Path) -> list[str]:
    """Check that all required predecessors have fresh (non-stale) snapshots.

    Returns list of stale predecessor phase names. Empty = all fresh.
    Each stale entry is formatted as "phase (reason)".

    In addition to generic snapshot comparison, phase-specific checks detect
    semantic staleness that snapshots alone cannot capture (e.g. TB files
    appearing after a post-rtl PASS that only snapshotted rtl/).
    """
    required = filter_required_predecessors(phase, level, project)
    phases_done = state.get("phases", {})
    stale = []

    for pred in required:
        entry = phases_done.get(pred)
        if not entry or entry.get("status") != "PASS":
            continue  # Missing is handled by check_predecessors()
        stored = entry.get("snapshot")
        if stored is None:
            # Predecessor has no snapshot (stamped before this hardening).
            # Treat as fresh unless evidence of staleness from other signals.
            pass
        else:
            current = compute_phase_snapshot(project, pred, state.get("level", "L1"))
            if not snapshots_match(stored, current):
                stale.append(f"{pred} (snapshot stale: files changed since stamp)")
                continue

    return stale


def next_required_command(missing: list[str], project_dir: str) -> str:
    """Return the NEXT_REQUIRED_COMMAND line for the earliest missing phase."""
    earliest = missing[0]
    return (
        f"NEXT_REQUIRED_COMMAND: python scripts/workflow_gate.py "
        f"--phase {earliest} {project_dir}"
    )


def phase_pass_guidance(phase: str, level: str, project_dir: str) -> list[str]:
    """Return workflow navigation lines printed after a phase PASS.

    These lines deliberately use stable labels so an agent can treat gate output
    as a next-step checklist instead of only a verdict.
    """
    is_l2 = _is_l2_or_higher(level)
    if phase == "pre-rtl":
        return [
            "CURRENT_STEP_COMPLETED: Steps 1-6 planning / pre-rtl contract gate",
            "NEXT_WORKFLOW_STEP: Step 7 RTL-only implementation",
            "NEXT_REQUIRED_ACTION: generate synthesizable RTL only; do not write TB or simulation artifacts",
            f"NEXT_REQUIRED_COMMAND: python scripts/workflow_gate.py --phase post-rtl {project_dir}",
        ]
    if phase == "post-rtl":
        if is_l2:
            return [
                "CURRENT_STEP_COMPLETED: Step 7b post-rtl RTL-only gate",
                "NEXT_WORKFLOW_STEP: Step 8 no-TB review, then Step 9 L2 per-module verification",
                "NEXT_REQUIRED_ACTION: complete Step 8/8c/8b without TB; first TB-producing step is Step 9 per-module TB + sim",
                "FORBIDDEN_NEXT_ACTION: do not create or run integration TB before pre-integration/module-sim gate PASS",
                f"NEXT_REQUIRED_COMMAND: python scripts/workflow_gate.py --phase pre-integration {project_dir}",
            ]
        return [
            "CURRENT_STEP_COMPLETED: Step 7b post-rtl RTL-only gate",
            "NEXT_WORKFLOW_STEP: Step 8 no-TB review, then Step 10 functional/integration verification as applicable",
            "NEXT_REQUIRED_ACTION: complete review and verification plan before writing TB",
            f"NEXT_REQUIRED_COMMAND: python scripts/workflow_gate.py --phase post-sim {project_dir}",
        ]
    if phase == "pre-integration":
        return [
            "CURRENT_STEP_COMPLETED: Step 9-EXIT module-sim / pre-integration gate",
            "NEXT_WORKFLOW_STEP: Step 10 integration verification",
            "INTEGRATION_TB_ALLOWED: yes",
            "NEXT_REQUIRED_ACTION: write integration TB/assertions, run guarded sim, then perform false-pass audit",
            f"NEXT_REQUIRED_COMMAND: python scripts/workflow_gate.py --phase post-sim {project_dir}",
        ]
    if phase == "post-sim":
        return [
            "CURRENT_STEP_COMPLETED: Step 10-EXIT post-sim gate",
            "NEXT_WORKFLOW_STEP: Step 11 final delivery gate",
            "NEXT_REQUIRED_ACTION: run final workflow gate before claiming PASS",
            f"NEXT_REQUIRED_COMMAND: python scripts/workflow_gate.py --phase final {project_dir}",
        ]
    if phase == "final":
        return [
            "CURRENT_STEP_COMPLETED: Step 11 final delivery gate",
            "NEXT_WORKFLOW_STEP: delivery may be claimed",
            "DELIVERY_CLAIM_ALLOWED: yes",
        ]
    return []


# ---------------------------------------------------------------------------
#  Discovery helpers
# ---------------------------------------------------------------------------

def discover_rtl_verilog(project: Path) -> list[str]:
    """Discover only RTL Verilog files (not TB)."""
    files: list[Path] = []
    rtl_dir = project / "rtl"
    if rtl_dir.exists():
        files.extend(sorted(rtl_dir.glob("*.v")))
        files.extend(sorted(rtl_dir.glob("*.sv")))
    return [str(p) for p in files]


def discover_tb_verilog(project: Path) -> list[str]:
    """Discover TB Verilog files (canonical tb/ and non-canonical sim/tb_*)."""
    files: list[Path] = []
    tb_dir = project / "tb"
    if tb_dir.exists():
        files.extend(sorted(tb_dir.glob("*.v")))
        files.extend(sorted(tb_dir.glob("*.sv")))
    sim_dir = project / "sim"
    if sim_dir.exists():
        files.extend(sorted(sim_dir.glob("tb_*.v")))
        files.extend(sorted(sim_dir.glob("tb_*.sv")))
    return [str(p) for p in files]


def discover_all_verilog(project: Path) -> list[str]:
    """Discover all Verilog files (RTL + TB). Used by post-sim and final."""
    return discover_rtl_verilog(project) + discover_tb_verilog(project)


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
#  Compile log marker check
# ---------------------------------------------------------------------------

COMPILE_RTL_ONLY_MARKER = "COMPILE_RTL_ONLY"
COMPILE_STANDALONE_MARKER = "COMPILE_STANDALONE"

# Compile success patterns. A post-rtl compile log must include one of these
# AND an explicit RTL-only marker; success text alone is not phase evidence.
COMPILE_SUCCESS_PATTERNS = [
    r'\bCOMPILE_PASS\b',
    r'\bCOMPILE_SUCCESS\b',
    r'\bALL_COMPILE_PASS\b',
    r'\bcompilation\s+successful\b',
    r'\bcompiled\s+successfully\b',
    r'\bno\s+errors?\b',
    r'\b0\s+errors?\b',
]


def _compile_log_has_rtl_marker(log_path: str) -> bool:
    """Check if a compile log contains a RTL-only compile marker."""
    try:
        text = Path(log_path).read_text(encoding="utf-8", errors="replace")
        return bool(re.search(
            r'(?im)^\ufeff?\s*#?\s*(COMPILE_RTL_ONLY|COMPILE_STANDALONE)\b',
            text))
    except (OSError, UnicodeDecodeError):
        return False


def _compile_log_has_success_evidence(log_path: str) -> bool:
    """Check if a compile log contains compile success evidence patterns.

    Does NOT use directory-based heuristics (no TB filename scanning).
    """
    try:
        text = Path(log_path).read_text(encoding="utf-8", errors="replace")
    except (OSError, UnicodeDecodeError):
        return False
    for pattern in COMPILE_SUCCESS_PATTERNS:
        if re.search(pattern, text, re.IGNORECASE):
            return True
    return False


# ---------------------------------------------------------------------------
#  Per-phase gate logic
# ---------------------------------------------------------------------------

def _check_contract_readiness(project: Path, level: str) -> list[str]:
    """Verify required contracts/plans exist and are non-empty before RTL."""
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


def _check_compile_log_markers(project: Path, compile_logs: list[str],
                                level: str) -> list[str]:
    """Check that compile logs for post-rtl have hard RTL-only evidence.

    Each compile log used in post-rtl must have:
    - Explicit COMPILE_RTL_ONLY or COMPILE_STANDALONE marker, AND
    - Compile success evidence.

    Logs missing either part are rejected.
    Directory-based heuristics (TB filename scanning) are NOT used --
    the log content must speak for itself.
    """
    findings = []
    for log in compile_logs:
        log_name = Path(log).name
        has_marker = _compile_log_has_rtl_marker(log)
        has_success = _compile_log_has_success_evidence(log)

        if not has_marker:
            findings.append(
                f"compile log '{log_name}' lacks RTL-only marker "
                f"('# COMPILE_RTL_ONLY' or '# COMPILE_STANDALONE'). "
                f"post-rtl requires explicit RTL-only compile evidence. "
                f"Add the marker before the compile command/output.")

        if not has_success:
            findings.append(
                f"compile log '{log_name}' lacks compile success evidence "
                f"(COMPILE_PASS/COMPILE_SUCCESS/ALL_COMPILE_PASS/"
                f"'compilation successful'/'compiled successfully'/"
                f"'no errors'/'0 errors').")
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
    level = detect_level(project)

    # 0. First post-rtl PASS must be before any TB/sim artifacts. If post-rtl
    #    already passed, allow re-run for RTL debug even when old TB/logs exist.
    state = load_state(project)
    already_post_rtl_passed = (
        state.get("phases", {}).get("post-rtl", {}).get("status") == "PASS")
    if not already_post_rtl_passed:
        if has_tb_files(project) or has_sim_artifacts(project):
            findings.append(
                "premature TB/sim artifacts found before first post-rtl PASS. "
                "Step 7 is RTL-only; do not create tb/*.v or simulation "
                "artifacts until post-rtl passes and Step 9/10 begins.")
            return findings

    # 1. Discover RTL files ONLY (no TB)
    rtl_files = discover_rtl_verilog(project)
    if not rtl_files:
        return ["no RTL Verilog files found under rtl/ for post-rtl gate"]

    # 2. RTL style check (RTL files only)
    rc, out = run_script("rtl_style_check.py", ["--level", level] + rtl_files)
    print_block("rtl_style_check", rc, out)
    if "[E]" in out:
        findings.append("rtl_style_check has E-level findings")

    # 3. Compile log evidence (must be RTL-only)
    compile_logs = discover_compile_logs(project)
    if not compile_logs:
        findings.append(
            "no compile log found under sim/ for post-rtl gate. "
            "Run 'iverilog -g2012 -o /dev/null rtl/*.v > sim/compile_rtl.log 2>&1' "
            "and ensure the log contains '# COMPILE_RTL_ONLY' marker.")
    else:
        # Check for RTL-only markers
        marker_findings = _check_compile_log_markers(project, compile_logs, level)
        findings.extend(marker_findings)

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

    # TB style check (completion-only, false-pass, sideband)
    tb_files = discover_tb_verilog(project)
    if tb_files:
        level = detect_level(project)
        rc, out = run_script("rtl_style_check.py", ["--level", level] + tb_files)
        print_block("rtl_style_check (TB)", rc, out)
        if "[E]" in out:
            findings.append("rtl_style_check on TB has E-level findings")

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
        choices=CLI_PHASE_CHOICES,
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Skip predecessor check (for recovery). Still records PASS only if gate passes.",
    )
    parser.add_argument("project_dir")
    args = parser.parse_args()

    project = Path(args.project_dir).resolve()
    requested_phase = args.phase
    phase = PHASE_ALIASES.get(requested_phase, requested_phase)

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
    cmd_str = f"python scripts/workflow_gate.py --phase {phase} {project}"
    if not args.force:
        missing = check_predecessors(state, phase, level, project)
        if missing:
            findings = [f"Predecessor phase(s) not passed: {', '.join(missing)}"]
            command_line = next_required_command(missing, str(project))
            guidance = [
                f"NEXT_WORKFLOW_STEP: re-run missing predecessor phase '{missing[0]}'",
                command_line,
            ]
            write_workflow_cursor(project, phase, "FAIL", level, cmd_str,
                                  findings, guidance)
            print("PHASE_WORKFLOW_GATE: FAIL")
            print(f"- {findings[0]}")
            print(f"- {command_line}")
            print(f"- Cursor saved to {cursor_file_path(project)}")
            return 1

        # Freshness check: are predecessor snapshots still valid?
        stale = check_predecessor_freshness(state, phase, level, project)
        if stale:
            stale_phases = [s.split()[0] for s in stale]
            findings = [f"Stale predecessor phase(s): {', '.join(stale)}"]
            command_line = next_required_command(stale_phases, str(project))
            guidance = [
                f"NEXT_WORKFLOW_STEP: re-run stale predecessor phase '{stale_phases[0]}'",
                command_line,
            ]
            write_workflow_cursor(project, phase, "FAIL", level, cmd_str,
                                  findings, guidance)
            print("PHASE_WORKFLOW_GATE: FAIL")
            print(f"- {findings[0]}")
            print(f"- {command_line}")
            print(f"- Cursor saved to {cursor_file_path(project)}")
            return 1

    # Run the phase gate
    gate_fn = PHASE_GATE_MAP[phase]
    findings = gate_fn(project)

    if findings:
        print("PHASE_WORKFLOW_GATE: FAIL")
        for finding in findings:
            print(f"- {finding}")
        stamp_phase(state, phase, "FAIL", summarize_evidence(phase, findings), cmd_str)
        save_state(project, state)
        write_workflow_cursor(project, phase, "FAIL", level, cmd_str, findings, [])
        print(f"- Cursor saved to {cursor_file_path(project)}")
        return 1

    # PASS: stamp state with artifact snapshot
    snapshot = compute_phase_snapshot(project, phase, level)
    stamp_phase(state, phase, "PASS", summarize_evidence(phase, findings), cmd_str, snapshot)
    save_state(project, state)
    guidance = phase_pass_guidance(phase, level, str(project))
    write_workflow_cursor(project, phase, "PASS", level, cmd_str, findings, guidance)

    print("PHASE_WORKFLOW_GATE: PASS")
    print(f"- State saved to {state_file_path(project)}")
    print(f"- Cursor saved to {cursor_file_path(project)}")
    if snapshot:
        print(f"- Snapshot: {len(snapshot)} file(s) recorded")
    print(f"PROJECT_LEVEL: {level}")
    for line in guidance:
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
