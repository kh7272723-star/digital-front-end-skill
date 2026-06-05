"""Final delivery gate: orchestrates all gating scripts for project delivery.

Orchestrates project_artifact_gate, pre_integration_gate, rtl_style_check,
compile_log_gate, and sim_log_gate into a single pipeline. Exit 0 only when
ALL components pass.

Usage:
    python scripts/final_delivery_gate.py <project_dir>
        [--compile-log LOG ...] [--sim-log LOG ...] [--rtl-file FILE ...]
"""
import argparse
import os
import re
import subprocess
import sys
import io


try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')
except (AttributeError, io.UnsupportedOperation):
    try:
        sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
        sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8', errors='replace')
    except AttributeError:
        pass


def _script_dir() -> str:
    """Return the directory containing this script."""
    return os.path.dirname(os.path.abspath(__file__))


def _run_script(script_name: str, args: list[str]) -> tuple[int, str]:
    """Run a sibling script via subprocess and return (returncode, combined output)."""
    script_path = os.path.join(_script_dir(), script_name)
    cmd = [sys.executable, script_path] + args
    env = os.environ.copy()
    env.setdefault('PYTHONIOENCODING', 'utf-8')
    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        encoding='utf-8',
        errors='replace',
        env=env)
    output = result.stdout
    if result.stderr:
        output += '\n' + result.stderr
    return result.returncode, output


# ---------------------------------------------------------------------------
# Step 1 -- project_artifact_gate
# ---------------------------------------------------------------------------

def step1_project_artifact_gate(project_dir: str) -> list[str]:
    """Run project_artifact_gate.py.  Return list of findings (empty = PASS)."""
    findings: list[str] = []
    rc, output = _run_script('project_artifact_gate.py', [project_dir])
    if rc != 0:
        findings.append("PROJECT_ARTIFACT_GATE failed")
        for line in output.splitlines():
            stripped = line.strip()
            if stripped.startswith('- ') or stripped.startswith('[REJECT]'):
                findings.append(f"  artifact: {stripped}")
    return findings


def step1b_pre_integration_gate(project_dir: str) -> list[str]:
    """Run pre_integration_gate.py.  Return list of findings (empty = PASS)."""
    findings: list[str] = []
    rc, output = _run_script('pre_integration_gate.py', [project_dir])
    if rc != 0:
        findings.append("PRE_INTEGRATION_GATE failed")
        for line in output.splitlines():
            stripped = line.strip()
            if stripped.startswith('- ') or stripped.startswith('[REJECT]'):
                findings.append(f"  pre_integration: {stripped}")
    return findings


# ---------------------------------------------------------------------------
# Step 2 -- rtl_style_check
# ---------------------------------------------------------------------------

def _discover_rtl_files(project_dir: str) -> list[str]:
    """Discover RTL files and canonical/non-canonical TB files.

    Canonical TB placement is tb/.  sim/tb_*.v is still scanned so false-pass
    testbench checks run even when project_artifact_gate separately reports the
    non-canonical placement.
    """
    files: list[str] = []
    for subdir in ('rtl', 'tb'):
        d = os.path.join(project_dir, subdir)
        if os.path.isdir(d):
            for fname in sorted(os.listdir(d)):
                if fname.endswith(('.v', '.sv')):
                    files.append(os.path.join(d, fname))
    sim_dir = os.path.join(project_dir, 'sim')
    if os.path.isdir(sim_dir):
        for fname in sorted(os.listdir(sim_dir)):
            if fname.startswith('tb_') and fname.endswith(('.v', '.sv')):
                files.append(os.path.join(sim_dir, fname))
    return files


def _detect_project_level(project_dir: str) -> str:
    """Detect project level for passing to rtl_style_check --level.

    Mirrors the artifact-gate hardening: artifact-based L2 evidence must not
    be downgraded by a silent dev_log, because RSP2 severity depends on this
    value.
    """
    logged_level = None
    for dev_log in [
        os.path.join(project_dir, 'docs', 'dev_log.md'),
        os.path.join(project_dir, 'dev_log.md'),
    ]:
        if os.path.isfile(dev_log):
            try:
                with open(dev_log, 'r', encoding='utf-8', errors='replace') as f:
                    text = f.read(500)
                if re.search(r'\bL2\b', text):
                    logged_level = 'L2'
                if re.search(r'\bL0\b', text):
                    logged_level = 'L0'
            except OSError:
                pass
    # Artifact-based fallback
    rtl_dir = os.path.join(project_dir, 'rtl')
    if os.path.isdir(rtl_dir):
        rtl_files = [f for f in os.listdir(rtl_dir) if f.endswith(('.v', '.sv'))]
        if len(rtl_files) >= 3:
            return 'L2'
        all_text = ''
        for fname in rtl_files:
            try:
                with open(os.path.join(rtl_dir, fname), 'r', encoding='utf-8',
                          errors='replace') as f:
                    all_text += f.read() + '\n'
            except OSError:
                pass
        has_nvme = bool(re.search(
            r'\b(prp1|prp2|slba|nlb|cpl_status)\b', all_text, re.IGNORECASE))
        has_dma = bool(re.search(
            r'\b(dma|burst_len|transfer_size|descriptor)\b', all_text, re.IGNORECASE))
        has_nand = bool(re.search(
            r'\b(nand|page_program|page_read|block_erase)\b', all_text, re.IGNORECASE))
        has_axi = bool(re.search(
            r'\b(m_axi_awvalid|m_axi_wvalid|awaddr|awlen)\b', all_text, re.IGNORECASE))
        if (has_nvme or has_dma or has_nand) and has_axi:
            return 'L2'
        module_names = re.findall(
            r'^\s*module\s+([A-Za-z_]\w*)\b', all_text, re.MULTILINE)
        if len(module_names) >= 3:
            module_set = set(module_names)
            for body_m in re.finditer(
                    r'^\s*module\s+([A-Za-z_]\w*)\b(.*?)(?=^\s*endmodule\b)',
                    all_text, re.MULTILINE | re.DOTALL):
                parent = body_m.group(1)
                body = body_m.group(2)
                instantiated = {
                    mod for mod in module_set
                    if mod != parent and
                    re.search(r'\b' + re.escape(mod) + r'\s+\w+\s*\(', body)
                }
                if len(instantiated) >= 2:
                    return 'L2'
    if logged_level:
        return logged_level
    return 'L1'


def step2_rtl_style_check(project_dir: str,
                          explicit_rtl_files: list[str]) -> list[str]:
    """Discover RTL/TB files and run rtl_style_check.py.  Return findings."""
    findings: list[str] = []

    rtl_files = list(explicit_rtl_files) if explicit_rtl_files else []
    if not rtl_files:
        rtl_files = _discover_rtl_files(project_dir)

    if not rtl_files:
        findings.append("No RTL/TB files found to check")
        return findings

    level = _detect_project_level(project_dir)
    style_args = ['--level', level] + rtl_files
    rc, output = _run_script('rtl_style_check.py', style_args)
    if rc != 0:
        for line in output.splitlines():
            stripped = line.strip()
            if stripped.startswith('['):
                findings.append(f"  rtl_style: {stripped}")
        if not findings:
            findings.append(f"rtl_style_check.py exited with code {rc}")
    return findings


# ---------------------------------------------------------------------------
# Step 3 -- compile_log_gate
# ---------------------------------------------------------------------------


def _auto_discover_compile_logs(project_dir: str) -> list[str]:
    """Scan sim/*.log for content matching compile-related keywords."""
    logs: list[str] = []
    sim_dir = os.path.join(project_dir, 'sim')
    if not os.path.isdir(sim_dir):
        return logs

    combined_pat = re.compile(
        r'(warning:|error:|syntax\s+error|compil|selecting\s+(?:after|before)|'
        r'out\s+of\s+bound|Replacing.*(?:\'\s*bx|\bwith\s+x\b)|'
        r'\bPort\b.*\bexpects\b.*\bgot\b|padding|pruning|truncat|'
        r'inferred\s+latch|latch\s+inferred)',
        re.IGNORECASE)

    for fname in sorted(os.listdir(sim_dir)):
        if not fname.endswith('.log'):
            continue
        fpath = os.path.join(sim_dir, fname)
        if re.search(r'(compile|build|iverilog|vlog|verilator)', fname, re.IGNORECASE):
            logs.append(fpath)
            continue
        try:
            with open(fpath, 'rb') as f:
                raw = f.read(4096)  # read head only for quick scan
            text = raw.decode('utf-8', errors='replace')
            if '\x00' in text:
                text = text.replace('\x00', '')
            if combined_pat.search(text):
                logs.append(fpath)
        except OSError:
            pass
    return logs


def step3_compile_log_check(project_dir: str,
                            explicit_logs: list[str]) -> list[str]:
    """Run compile_log_gate.py on compile logs. Return findings."""
    findings: list[str] = []

    compile_logs = list(explicit_logs) if explicit_logs else []
    if not compile_logs:
        compile_logs = _auto_discover_compile_logs(project_dir)

    if not compile_logs:
        findings.append("No compile log found (required)")
        return findings

    existing_logs: list[str] = []
    for log_path in compile_logs:
        if not os.path.isfile(log_path):
            findings.append(f"Compile log not found: {log_path}")
            continue
        existing_logs.append(log_path)

    if existing_logs:
        rc, output = _run_script('compile_log_gate.py', existing_logs)
        if rc != 0:
            for line in output.splitlines():
                stripped = line.strip()
                if (stripped.startswith('- ') or
                        stripped.startswith('[REJECT]') or
                        stripped.endswith('finding(s)')):
                    findings.append(f"  compile_log: {stripped}")

    return findings


# ---------------------------------------------------------------------------
# Step 4 -- sim_log_gate
# ---------------------------------------------------------------------------

_SIM_MARKER_PATTERN = re.compile(
    r'(TEST|PASS|FAIL|TIMEOUT|SIMULATION|ALL_TESTS_PASS)', re.IGNORECASE)


def _auto_discover_sim_logs(project_dir: str) -> list[str]:
    """Scan sim/*.log for simulation markers."""
    logs: list[str] = []
    sim_dir = os.path.join(project_dir, 'sim')
    if not os.path.isdir(sim_dir):
        return logs

    for fname in sorted(os.listdir(sim_dir)):
        if not fname.endswith('.log'):
            continue
        fpath = os.path.join(sim_dir, fname)
        try:
            with open(fpath, 'rb') as f:
                raw = f.read(4096)
            text = raw.decode('utf-8', errors='replace')
            if '\x00' in text:
                text = text.replace('\x00', '')
            if _SIM_MARKER_PATTERN.search(text):
                logs.append(fpath)
        except OSError:
            pass
    return logs


def step4_sim_log_gate(project_dir: str,
                       explicit_logs: list[str]) -> list[str]:
    """Run sim_log_gate.py on sim logs.  Return findings."""
    findings: list[str] = []

    sim_logs = list(explicit_logs) if explicit_logs else []
    if not sim_logs:
        sim_logs = _auto_discover_sim_logs(project_dir)

    if not sim_logs:
        findings.append("No sim log found (required)")
        return findings

    for log_path in sim_logs:
        if not os.path.isfile(log_path):
            findings.append(f"Sim log not found: {log_path}")
            continue
        rc, output = _run_script('sim_log_gate.py', [log_path])
        if rc != 0:
            for line in output.splitlines():
                stripped = line.strip()
                if stripped.startswith('- '):
                    findings.append(f"  sim_log: {stripped}")

    return findings


# ---------------------------------------------------------------------------
# Step 5 -- runtime / runaway guard
# ---------------------------------------------------------------------------

# Default thresholds
MAX_VCD_BYTES  = 50 * 1024 * 1024   # 50 MB
MAX_LOG_BYTES  = 20 * 1024 * 1024   # 20 MB
MAX_VCD_FILES  = 3                  # more than this suggests runaway


def step5_runtime_guard(project_dir: str) -> list[str]:
    """Scan sim/ for oversized VCD/FST/logs and missing sim log evidence."""
    findings: list[str] = []
    sim_dir = os.path.join(project_dir, 'sim')
    if not os.path.isdir(sim_dir):
        findings.append("No sim/ directory found -- cannot verify runtime artifacts")
        return findings

    vcd_count = 0
    log_count = 0
    for fname in sorted(os.listdir(sim_dir)):
        fpath = os.path.join(sim_dir, fname)
        try:
            fsize = os.path.getsize(fpath)
        except OSError:
            continue

        if fname.endswith(('.vcd', '.fst', '.vpd', '.fsdb')):
            vcd_count += 1
            if fsize > MAX_VCD_BYTES:
                findings.append(
                    f"Runaway VCD: {fname} is {fsize:,} bytes "
                    f"(> {MAX_VCD_BYTES:,} limit). "
                    "Disable VCD dump by default; enable only during debug.")
        if fname.endswith('.log'):
            log_count += 1
            if fsize > MAX_LOG_BYTES:
                findings.append(
                    f"Oversized sim log: {fname} is {fsize:,} bytes "
                    f"(> {MAX_LOG_BYTES:,} limit). "
                    "Disable verbose per-beat logging; use only TEST_START/PASS/FAIL.")

    if vcd_count > MAX_VCD_FILES:
        findings.append(
            f"Excessive VCD/FST files: {vcd_count} found "
            f"(> {MAX_VCD_FILES} limit). Possible runaway simulation.")
    if log_count == 0:
        findings.append("No sim log found (required) -- runaway or missing sim evidence")
    if vcd_count > 0 and log_count == 0:
        findings.append("VCD present but no sim log -- cannot verify PASS evidence; "
                        "simulation may have been runaway or incomplete")

    # Standard log artifact requirement: .vvp without .log is insufficient evidence
    vvp_count = sum(1 for f in os.listdir(sim_dir) if f.endswith('.vvp'))
    if vvp_count > 0 and log_count == 0:
        findings.append(
            f"Found {vvp_count} .vvp file(s) but no .log files. "
            "Standard delivery requires .log evidence from run_sim_guarded.py. "
            "Bare vvp execution without log capture is not acceptable evidence.")

    return findings


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Final delivery gate: orchestrates all gating scripts.")
    parser.add_argument('project_dir', help='Project directory to check')
    parser.add_argument('--compile-log', action='append', default=[],
                        help='Explicit compile log file(s)')
    parser.add_argument('--sim-log', action='append', default=[],
                        help='Explicit simulation log file(s)')
    parser.add_argument('--rtl-file', action='append', default=[],
                        help='Explicit RTL/TB file(s) to check')
    args = parser.parse_args()

    project_dir = args.project_dir
    if not os.path.isdir(project_dir):
        print(f"[REJECT] Not a directory: {project_dir}", file=sys.stderr)
        sys.exit(1)

    all_findings: list[str] = []

    # Step 1 -- project_artifact_gate
    findings = step1_project_artifact_gate(project_dir)
    all_findings.extend(('  step1: ' + f) for f in findings)

    # Step 1b -- pre-integration lock (L2 only)
    findings = step1b_pre_integration_gate(project_dir)
    all_findings.extend(('  step1b: ' + f) for f in findings)

    # Step 2 -- RTL style check
    findings = step2_rtl_style_check(project_dir, args.rtl_file)
    all_findings.extend(('  step2: ' + f) for f in findings)

    # Step 3 -- compile log check
    findings = step3_compile_log_check(project_dir, args.compile_log)
    all_findings.extend(('  step3: ' + f) for f in findings)

    # Step 4 -- simulation log gate
    findings = step4_sim_log_gate(project_dir, args.sim_log)
    all_findings.extend(('  step4: ' + f) for f in findings)

    # Step 5 -- runtime / runaway guard
    findings = step5_runtime_guard(project_dir)
    all_findings.extend(('  step5: ' + f) for f in findings)

    if not all_findings:
        print("FINAL_DELIVERY_GATE: PASS")
        sys.exit(0)

    print("FINAL_DELIVERY_GATE: FAIL")
    for f in all_findings:
        print(f"  - {f}")
    sys.exit(1)


if __name__ == '__main__':
    main()
