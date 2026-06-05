"""Pre-integration simulation lock: reject L2 projects that skip per-module simulation.

For L2 multi-module projects, integration simulation must NOT start until every
RTL module has per-module simulation/proof evidence.  This gate catches the
anti-pattern of writing an integration TB and running integration sim before
per-module evidence exists.

Detection:
  - L2 project with >=2 rtl/*.v modules
  - Integration TB exists: tb/tb_<top>.v or any TB instantiating top-level module
  - Per-module TB or evidence missing for any leaf module
  - Integration sim artifact (log/vvp) exists without per-module evidence

Usage: python scripts/pre_integration_gate.py <project_dir>
Exit code: 0 = clean, 1 = violations found, 2 = usage error.
"""
import argparse
import io
import os
import re
import sys


try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')
except (AttributeError, io.UnsupportedOperation):
    try:
        sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
        sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8', errors='replace')
    except AttributeError:
        pass


def _read_file(path: str) -> str:
    if not os.path.isfile(path):
        return ''
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        return f.read()


def _detect_level(proj_dir: str) -> str:
    """Best-effort detect if project is L2."""
    for dev_log in [
        os.path.join(proj_dir, 'docs', 'dev_log.md'),
        os.path.join(proj_dir, 'dev_log.md'),
    ]:
        text = _read_file(dev_log)
        if re.search(r'\bL2\b', text[:500]):
            return 'L2'
        if re.search(r'\bL0\b', text[:500]):
            return 'L0'

    # Artifact-based inference
    rtl_dir = os.path.join(proj_dir, 'rtl')
    if os.path.isdir(rtl_dir):
        rtl_files = [f for f in os.listdir(rtl_dir) if f.endswith(('.v', '.sv'))]
        if len(rtl_files) >= 3:
            return 'L2'
        # Check for multi-protocol signals
        all_text = ''
        for fname in rtl_files:
            all_text += _read_file(os.path.join(rtl_dir, fname))
        has_nvme = bool(re.search(r'\b(prp1|prp2|slba|nlb|cpl_status)\b', all_text, re.IGNORECASE))
        has_dma = bool(re.search(r'\b(dma|burst_len|transfer_size|descriptor)\b', all_text, re.IGNORECASE))
        has_nand = bool(re.search(r'\b(nand|page_program|page_read|block_erase)\b', all_text, re.IGNORECASE))
        has_axi = bool(re.search(r'\b(m_axi_awvalid|m_axi_wvalid|awaddr|awlen)\b', all_text, re.IGNORECASE))
        if (has_nvme or has_dma or has_nand) and has_axi:
            return 'L2'
        module_names = re.findall(r'^\s*module\s+([A-Za-z_]\w*)\b', all_text, re.MULTILINE)
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
        tb_dir = os.path.join(proj_dir, 'tb')
        if os.path.isdir(tb_dir) and len(rtl_files) >= 2:
            return 'L2'

    return 'L1'


def _parse_rtl_modules(proj_dir: str) -> dict[str, str]:
    """Return {module_name: filename} for rtl/*.v files."""
    modules = {}
    rtl_dir = os.path.join(proj_dir, 'rtl')
    if not os.path.isdir(rtl_dir):
        return modules
    for fname in os.listdir(rtl_dir):
        if not fname.endswith(('.v', '.sv')):
            continue
        text = _read_file(os.path.join(rtl_dir, fname))
        for m in re.finditer(r'^\s*module\s+([A-Za-z_]\w*)\b', text, re.MULTILINE):
            modules[m.group(1)] = fname
    return modules


def _find_tb_files(proj_dir: str) -> list[str]:
    """Return list of TB file paths (canonical tb/ and sim/tb_*)."""
    tbs = []
    for subdir in ('tb', 'sim'):
        d = os.path.join(proj_dir, subdir)
        if not os.path.isdir(d):
            continue
        for fname in sorted(os.listdir(d)):
            if fname.endswith(('.v', '.sv')) and (fname.startswith('tb_') or subdir == 'tb'):
                tbs.append(os.path.join(d, fname))
    return tbs


def _detect_integration_tb(tb_files: list[str], modules: dict[str, str]) -> list[str]:
    """Return list of TB files that appear to be integration TBs.

    An integration TB instantiates multiple RTL leaf modules or a top-level
    module that itself instantiates other modules.
    """
    integration_tbs = []
    module_names = set(modules.keys())

    for tb_path in tb_files:
        text = _read_file(tb_path)
        # Count distinct module instantiations from RTL modules
        instantiated = set()
        for mod_name in module_names:
            # Match instantiation: module_name instance_name (
            if re.search(r'\b' + re.escape(mod_name) + r'\s+\w+\s*\(', text):
                instantiated.add(mod_name)

        if len(instantiated) >= 2:
            integration_tbs.append(tb_path)
        elif len(instantiated) == 1:
            # Single module instantiation could be per-module TB -- check if
            # the instantiated module is a top-level that itself is multi-module
            # (heuristic: if tb file is named tb_<top>.v and <top> is a module)
            tb_basename = os.path.basename(tb_path).replace('.v', '').replace('.sv', '')
            top_candidate = tb_basename.replace('tb_', '', 1)
            if top_candidate in module_names and len(module_names) >= 3:
                integration_tbs.append(tb_path)

    return integration_tbs


def _has_module_evidence(proj_dir: str, module_name: str) -> bool:
    """Check if a module has per-module TB or evidence."""
    # Check for per-module TB: tb/tb_<module>.v
    for subdir in ('tb', 'sim'):
        tb_path = os.path.join(proj_dir, subdir, f'tb_{module_name}.v')
        if os.path.isfile(tb_path):
            return True
        tb_path_sv = os.path.join(proj_dir, subdir, f'tb_{module_name}.sv')
        if os.path.isfile(tb_path_sv):
            return True

    # Check module_verification_matrix.md for evidence
    matrix_path = os.path.join(proj_dir, 'docs', 'module_verification_matrix.md')
    matrix_text = _read_file(matrix_path)
    if not matrix_text:
        return False

    for line in matrix_text.splitlines():
        if re.search(r'\b' + re.escape(module_name) + r'\b', line, re.IGNORECASE):
            # Check for evidence log path or waiver
            has_log = bool(re.search(
                r'(sim|logs|formal|out|build)[/\\][^|\s,;]+?\.(?:log|out|txt)',
                line, re.IGNORECASE))
            has_waiver = bool(re.search(
                r'\b(waiver|waived|integration[-\s]?only|top[-\s]?level|trivial)\b',
                line, re.IGNORECASE))
            if has_log or has_waiver:
                return True

    return False


def _find_integration_sim_artifacts(proj_dir: str) -> list[str]:
    """Find integration sim logs/vvp/extensionless outputs without per-module evidence.

    Detects:
    - .log and .vvp files (standard)
    - Extensionless Icarus outputs (e.g. sim/tb_nand_page_ctrl) that match
      TB or top-module naming patterns.  Icarus 'iverilog -o sim/foo ...'
      produces extensionless executables; these are sim artifacts, not build logs.
    - Ignores ordinary compile/build logs (compile.log, build.log, etc.)
    """
    artifacts = []
    sim_dir = os.path.join(proj_dir, 'sim')
    if not os.path.isdir(sim_dir):
        return artifacts

    for fname in sorted(os.listdir(sim_dir)):
        fpath = os.path.join(sim_dir, fname)
        if not os.path.isfile(fpath):
            continue
        # Skip ordinary compile/build logs
        if re.search(r'(compile|build|iverilog|vlog|verilator)', fname, re.IGNORECASE):
            continue
        # Standard artifacts: .log, .vvp
        if fname.endswith(('.log', '.vvp')):
            artifacts.append(fpath)
            continue
        # Extensionless Icarus outputs: file has no extension and matches
        # TB or top-module naming patterns (tb_*, top_*, integration_*)
        if '.' not in fname and re.search(r'^(tb_|top_|integration_)', fname, re.IGNORECASE):
            artifacts.append(fpath)
    return artifacts


def check_pre_integration(proj_dir: str) -> list[str]:
    """Main pre-integration gate check. Return list of findings."""
    findings = []

    level = _detect_level(proj_dir)
    if level != 'L2':
        return findings  # Only applies to L2

    modules = _parse_rtl_modules(proj_dir)
    if len(modules) < 2:
        return findings  # Single-module projects exempt

    # Find TB files and detect integration TBs
    tb_files = _find_tb_files(proj_dir)
    if not tb_files:
        return findings  # No TB files yet -- pre-integration, OK

    integration_tbs = _detect_integration_tb(tb_files, modules)

    # Check which modules lack per-module evidence
    missing_evidence = []
    for mod_name in sorted(modules.keys()):
        if not _has_module_evidence(proj_dir, mod_name):
            missing_evidence.append(mod_name)

    if not missing_evidence:
        return findings  # All modules have evidence

    # If integration TB exists but modules lack evidence, reject
    if integration_tbs:
        for tb in integration_tbs:
            tb_rel = os.path.relpath(tb, proj_dir)
            findings.append(
                f"PRE_INTEGRATION_LOCK: Integration TB '{tb_rel}' exists "
                f"but {len(missing_evidence)} module(s) lack per-module evidence: "
                f"{', '.join(missing_evidence)}. "
                f"L2 requires per-module simulation before integration. "
                f"Write tb/<module>.v and pass sim_log_gate for each module first.")

    # Check for integration sim artifacts (logs/vvp/extensionless) without per-module evidence
    sim_artifacts = _find_integration_sim_artifacts(proj_dir)
    if sim_artifacts and missing_evidence:
        # Check if any sim artifact looks like an integration sim
        for artifact in sim_artifacts:
            fname = os.path.basename(artifact)
            # Skip per-module logs/vvp (tb_<module>.log/vvp pattern)
            is_module_artifact = any(
                fname == f'tb_{mod}.log' or fname == f'tb_{mod}.vvp' or
                fname == f'tb_{mod}'
                for mod in modules
            )
            if is_module_artifact:
                continue
            findings.append(
                f"PRE_INTEGRATION_LOCK: Integration sim artifact '{fname}' "
                f"exists but {len(missing_evidence)} module(s) lack "
                f"per-module evidence: {', '.join(missing_evidence)}")

    return findings


def main():
    parser = argparse.ArgumentParser(
        description="Pre-integration simulation lock: reject L2 projects "
                    "that skip per-module simulation.")
    parser.add_argument('project_dir', help='Project directory to check')
    args = parser.parse_args()

    proj_dir = args.project_dir
    if not os.path.isdir(proj_dir):
        print(f"[REJECT] Not a directory: {proj_dir}", file=sys.stderr)
        sys.exit(2)

    findings = check_pre_integration(proj_dir)

    if not findings:
        print("PRE_INTEGRATION_GATE: PASS")
        sys.exit(0)

    print("PRE_INTEGRATION_GATE: FAIL")
    for f in findings:
        print(f"  - {f}")
    sys.exit(1)


if __name__ == '__main__':
    main()
