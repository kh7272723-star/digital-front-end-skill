"""Pre-integration simulation lock: reject L2 projects that skip per-module simulation.

For L2 multi-module projects, integration simulation must NOT start until every
RTL module has per-module simulation/proof evidence.  This gate catches the
anti-pattern of writing an integration TB and running integration sim before
per-module evidence exists.

Detection:
  - L2 project with >=2 rtl/*.v modules
  - Integration TB exists: tb/tb_<top>.v, parameterized instantiation of top
    module, or any TB instantiating top-level module
  - Per-module TB or evidence missing for any leaf module
  - Integration sim artifact (log/vvp) exists without per-module evidence

Hardened:
  - Detects parameterized instantiation patterns (module #(...) inst (...))
  - Validates matrix PASS evidence by running sim_log_gate on referenced logs
  - Tightens waiver: only "Accepted Limitation" with explicit reason counts;
    bare "waiver"/"trivial" words are no longer sufficient
  - FAIL logs (ALL_TESTS_FAIL/TEST_FAIL/FATAL/timeout) cannot claim PASS

Usage: python scripts/pre_integration_gate.py <project_dir>
Exit code: 0 = clean, 1 = violations found, 2 = usage error.
"""
import argparse
import io
import os
import re
import subprocess
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


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


def _run_sim_log_gate(log_path: str) -> tuple[int, str]:
    """Run sim_log_gate.py on a log file. Returns (rc, output)."""
    script = os.path.join(SCRIPT_DIR, 'sim_log_gate.py')
    try:
        result = subprocess.run(
            [sys.executable, script, log_path],
            capture_output=True, text=True, encoding='utf-8', errors='replace')
        return result.returncode, result.stdout + '\n' + result.stderr
    except (subprocess.SubprocessError, OSError) as e:
        return 1, f"Error running sim_log_gate: {e}"


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


def _strip_verilog_comments(text: str) -> str:
    """Remove Verilog comments before regex-based structure scans."""
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)
    text = re.sub(r'//.*', '', text)
    return text


def _instantiates_module(text: str, module_name: str) -> bool:
    """Return True if text instantiates a specific RTL module.

    Supports both:
      module_name inst_name (...);
      module_name #(...) inst_name (...);

    The regex is intentionally anchored to a known module name. A generic
    "word #(...) word (" pattern is too broad and misclassifies parameterized
    leaf-module TBs as integration TBs.
    """
    clean = _strip_verilog_comments(text)
    pattern = (
        r'\b' + re.escape(module_name) +
        r'\s*(?:#\s*\([^;]*?\)\s*)?'
        r'[A-Za-z_]\w*\s*\('
    )
    return bool(re.search(pattern, clean, re.DOTALL))


def _find_instantiated_modules(text: str, module_names: set[str]) -> set[str]:
    """Return known RTL modules instantiated by text."""
    return {m for m in module_names if _instantiates_module(text, m)}


def _detect_integration_tb(tb_files: list[str], modules: dict[str, str],
                           top_modules: set[str]) -> list[str]:
    """Return list of TB files that appear to be integration TBs.

    An integration TB:
    1. Instantiates multiple RTL leaf modules, OR
    2. Instantiates a top-level module that itself instantiates others, OR
    3. Instantiates a parameterized top-level RTL module
    """
    integration_tbs = []
    module_names = set(modules.keys())

    for tb_path in tb_files:
        text = _read_file(tb_path)

        instantiated = _find_instantiated_modules(text, module_names)

        # Integration TB signals:
        # A) Instantiates >= 2 distinct RTL modules
        if len(instantiated) >= 2:
            integration_tbs.append(tb_path)
            continue

        # B) Single known top/wrapper module instantiation
        if len(instantiated) == 1:
            instantiated_mod = next(iter(instantiated))
            if instantiated_mod in top_modules:
                integration_tbs.append(tb_path)
                continue

        # C) Fallback: TB name exactly targets a top/wrapper-like module name.
        if len(instantiated) == 1 and len(module_names) >= 3:
            tb_basename = os.path.basename(tb_path).replace('.v', '').replace('.sv', '')
            top_candidate = tb_basename.replace('tb_', '', 1)
            instantiated_mod = next(iter(instantiated))
            if (instantiated_mod == top_candidate and
                    re.search(r'(top|wrapper|integrat|subsystem|system)',
                              instantiated_mod, re.IGNORECASE)):
                integration_tbs.append(tb_path)
                continue

    return integration_tbs


def _line_has_pass_marker(line: str) -> bool:
    """Return True only for explicit completed/pass evidence, not a bare log path."""
    has_pass = bool(re.search(
        r'\b(PASS|ALL_TESTS_PASS|SIMULATION_DONE|PROVEN|FORMAL_PASS)\b',
        line, re.IGNORECASE))
    has_negative = bool(re.search(
        r'\b(FAIL|FAILED|NOT_RUN|PENDING|TBD|TODO|INCOMPLETE)\b',
        line, re.IGNORECASE))
    return has_pass and not has_negative


def _line_has_accepted_limitation(line: str) -> bool:
    """Return True only for explicit Accepted Limitation with reason.

    Tightened: bare 'waiver', 'trivial', or 'integration-only' are not
    sufficient by themselves. Must include 'Accepted Limitation' with
    an explanatory reason in the same context.
    """
    accepted = re.search(r'\bAccepted\s+Limitation\b(?P<tail>.*)$',
                         line, re.IGNORECASE)
    if accepted:
        tail = re.sub(r'[`|\s]+', ' ', accepted.group('tail')).strip()
        if len(tail) >= 8:
            return True

    # Allow explicit waivers with reason beyond just the word "waiver"
    has_waiver_with_reason = bool(re.search(
        r'\b(?:waiver|waived)\b.*\b(?:because|due\s+to|reason|since|'
        r'residual\s+risk|integration\s*[-]?\s*only)\b',
        line, re.IGNORECASE))
    if has_waiver_with_reason:
        return True

    return False


def _has_module_evidence(proj_dir: str, module_name: str) -> bool:
    """Check if a module has explicit PASS/proof evidence or waiver in matrix."""
    matrix_path = os.path.join(proj_dir, 'docs', 'module_verification_matrix.md')
    matrix_text = _read_file(matrix_path)
    if not matrix_text:
        return False

    for line in matrix_text.splitlines():
        if re.search(r'\b' + re.escape(module_name) + r'\b', line, re.IGNORECASE):
            if _line_has_pass_marker(line) or _line_has_accepted_limitation(line):
                return True

    return False


def _find_integration_sim_artifacts(proj_dir: str) -> list[str]:
    """Find integration sim logs/vvp/extensionless outputs without per-module evidence.

    Detects:
    - .log and .vvp files (standard)
    - Extensionless Icarus outputs (e.g. sim/tb_nand_page_ctrl) that match
      TB or top-module naming patterns.
    - Ignores ordinary compile/build logs.
    """
    artifacts = []
    sim_dir = os.path.join(proj_dir, 'sim')
    if not os.path.isdir(sim_dir):
        return artifacts

    for fname in sorted(os.listdir(sim_dir)):
        fpath = os.path.join(sim_dir, fname)
        if not os.path.isfile(fpath):
            continue
        if re.search(r'(compile|build|iverilog|vlog|verilator)', fname, re.IGNORECASE):
            continue
        if fname.endswith(('.log', '.vvp')):
            artifacts.append(fpath)
            continue
        if '.' not in fname and re.search(r'^(tb_|top_|integration_)', fname, re.IGNORECASE):
            artifacts.append(fpath)
    return artifacts


def _find_top_modules(proj_dir: str, modules: dict[str, str]) -> set[str]:
    """Identify top/wrapper modules that instantiate other RTL modules.

    A top/wrapper module either instantiates >= 2 distinct modules, or has a
    top/wrapper/integration-style name and instantiates at least one module.
    Returns set of top module names.
    """
    module_names = set(modules.keys())
    top_modules: set[str] = set()

    for mod_name, fname in modules.items():
        fpath = os.path.join(proj_dir, 'rtl', fname)
        text = _read_file(fpath)
        instantiated = set()
        for other_mod in module_names:
            if other_mod == mod_name:
                continue
            if _instantiates_module(text, other_mod):
                instantiated.add(other_mod)
        wrapper_named = bool(re.search(
            r'(top|wrapper|integrat|subsystem|system)', mod_name, re.IGNORECASE))
        file_named = bool(re.search(
            r'(top|wrapper|integrat|subsystem|system)', fname, re.IGNORECASE))
        if len(instantiated) >= 2 or (instantiated and (wrapper_named or file_named)):
            top_modules.add(mod_name)

    return top_modules


def _check_module_verification_matrix(proj_dir: str, modules: dict[str, str],
                                       top_modules: set[str]) -> list[str]:
    """Check that module_verification_matrix.md covers all non-top sub-modules.

    Each sub-module must have:
    1. Explicit PASS/proof evidence OR Accepted Limitation waiver
    2. If PASS is claimed, the referenced sim log must pass sim_log_gate
    3. FAIL/FATAL/timeout logs cannot be claimed as PASS
    """
    findings = []
    matrix_path = os.path.join(proj_dir, 'docs', 'module_verification_matrix.md')
    matrix_text = _read_file(matrix_path)

    if not matrix_text.strip():
        findings.append(
            "PRE_INTEGRATION_STRICT: L2 project requires "
            "docs/module_verification_matrix.md with per-module PASS evidence. "
            "Create it and record each sub-module's TB, sim log, and PASS status.")
        return findings

    # Sub-modules = all modules except top/wrapper
    sub_modules = {m for m in modules if m not in top_modules}
    if not sub_modules:
        return findings

    for mod_name in sorted(sub_modules):
        mod_found = False
        has_pass = False
        has_accepted_limitation = False
        evidence_logs = []

        for line in matrix_text.splitlines():
            if not re.search(r'\b' + re.escape(mod_name) + r'\b', line, re.IGNORECASE):
                continue
            mod_found = True
            if _line_has_pass_marker(line):
                has_pass = True
            if _line_has_accepted_limitation(line):
                has_accepted_limitation = True
            # Extract evidence log paths
            for m in re.finditer(
                    r'((?:sim|logs|formal|out|build)[/\\][^|\s,;]+?\.log)',
                    line, re.IGNORECASE):
                evidence_logs.append(m.group(1).strip('`"\''))

        if not mod_found:
            findings.append(
                f"PRE_INTEGRATION_STRICT: Sub-module '{mod_name}' not listed in "
                f"docs/module_verification_matrix.md. Add a row with TB, sim log, "
                f"and PASS evidence or Accepted Limitation waiver.")
            continue

        if has_accepted_limitation:
            continue  # Accepted Limitation is OK

        if not has_pass:
            findings.append(
                f"PRE_INTEGRATION_STRICT: Sub-module '{mod_name}' in matrix but "
                f"lacks PASS evidence or Accepted Limitation waiver. "
                f"Record sim log path with PASS marker, or add Accepted Limitation "
                f"with reason.")
            continue

        # Validate PASS evidence: referenced sim logs must pass sim_log_gate
        if not evidence_logs:
            findings.append(
                f"PRE_INTEGRATION_STRICT: Sub-module '{mod_name}' claims PASS but "
                f"has no sim log references in matrix. Add log path(s) with "
                f"ALL_TESTS_PASS and SIMULATION_DONE markers.")
            continue

        any_log_pass = False
        for rel_path in evidence_logs:
            full_path = os.path.normpath(os.path.join(proj_dir, rel_path))
            try:
                inside_project = (
                    os.path.commonpath([
                        os.path.abspath(proj_dir),
                        os.path.abspath(full_path),
                    ]) == os.path.abspath(proj_dir)
                )
            except ValueError:
                inside_project = False
            if not inside_project:
                findings.append(
                    f"PRE_INTEGRATION_STRICT: Sub-module '{mod_name}' evidence "
                    f"path escapes project: {rel_path}")
                continue
            if not os.path.isfile(full_path):
                findings.append(
                    f"PRE_INTEGRATION_STRICT: Sub-module '{mod_name}' evidence "
                    f"log not found: {rel_path}")
                continue

            # Run sim_log_gate on the referenced log
            rc, out = _run_sim_log_gate(full_path)
            if rc == 0:
                any_log_pass = True
            else:
                # Check if the log explicitly has FAIL/FATAL/timeout evidence
                log_text = _read_file(full_path)
                has_fail_evidence = bool(re.search(
                    r'\b(ALL_TESTS_FAIL|TEST_FAIL|FATAL|TIMEOUT)\b',
                    log_text, re.IGNORECASE))
                if has_fail_evidence:
                    findings.append(
                        f"PRE_INTEGRATION_STRICT: Sub-module '{mod_name}' claims "
                        f"PASS but sim log '{os.path.basename(full_path)}' contains "
                        f"FAIL/FATAL/timeout evidence. PASS claim is not valid "
                        f"when sim log shows failures.")
                else:
                    findings.append(
                        f"PRE_INTEGRATION_STRICT: Sub-module '{mod_name}' claims "
                        f"PASS but sim log '{os.path.basename(full_path)}' does "
                        f"not pass sim_log_gate. Fix sim issues or add "
                        f"Accepted Limitation with reason.")

        if not any_log_pass:
            # No valid log found
            findings.append(
                f"PRE_INTEGRATION_STRICT: Sub-module '{mod_name}' has no sim log "
                f"that passes sim_log_gate. All referenced logs either missing or "
                f"failed gate check.")

    return findings


def check_pre_integration(proj_dir: str) -> list[str]:
    """Main pre-integration gate check. Return list of findings.

    For L2 projects with >= 2 RTL modules:
    1. Strict: require module_verification_matrix.md with per-module PASS
       evidence for all non-top sub-modules (even without integration TB).
       PASS evidence must pass sim_log_gate on referenced logs.
    2. Existing: reject integration TB/sim artifacts before per-module evidence.
    """
    findings = []

    level = _detect_level(proj_dir)
    if level != 'L2':
        return findings  # Only applies to L2

    modules = _parse_rtl_modules(proj_dir)
    if len(modules) < 2:
        return findings  # Single-module projects exempt

    # --- Strict gate: require module verification matrix for L2 ---
    top_modules = _find_top_modules(proj_dir, modules)
    findings.extend(_check_module_verification_matrix(proj_dir, modules, top_modules))

    # --- Existing gate: integration TB/sim artifacts before per-module evidence ---
    tb_files = _find_tb_files(proj_dir)
    if not tb_files:
        return findings

    integration_tbs = _detect_integration_tb(tb_files, modules, top_modules)

    # Check which modules lack per-module evidence
    top_modules = _find_top_modules(proj_dir, modules)
    modules_to_check = [m for m in sorted(modules.keys()) if m not in top_modules]
    missing_evidence = []
    for mod_name in modules_to_check:
        if not _has_module_evidence(proj_dir, mod_name):
            missing_evidence.append(mod_name)

    if not missing_evidence:
        return findings

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
