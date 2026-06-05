#!/usr/bin/env python3
"""Project preflight gate: verify project skeleton before any RTL is written.

This gate runs before RTL generation to ensure the project directory has the
required skeleton structure. It is distinct from project_artifact_gate.py which
checks final delivery completeness after RTL + simulation.

Checks:
  - For L0:  dev_log.md + a module target
  - For L1:  docs/, rtl/, tb/, sim/ directories + 7 skeleton files under docs/ (No-SPEC)
  - For L2:  docs/, rtl/, tb/, sim/ directories + 7 skeleton files under docs/ (No-SPEC)
  - Skeleton files may be empty / placeholder (existence check only, not content).

Level is auto-detected from docs/dev_log.md (keywords L0/L1/L2) or inferred from
directory structure when dev_log.md is absent.

Usage: python scripts/project_preflight_gate.py <project_dir>
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


# ---------------------------------------------------------------------------
#  Detection helpers  (mirror project_artifact_gate.py semantics)
# ---------------------------------------------------------------------------

def _detect_user_spec(text: str) -> bool:
    """Return True only for affirmative evidence of an external/user SPEC."""
    if re.search(
        r'\b(no|without|missing)\s+(?:user\s+|external\s+|provided\s+)?spec\b|'
        r'\bno-spec\b|'
        r'\bno\s+(?:project\s+)?spec\s+provided\b|'
        r'\bfrom\s+scratch\b',
        text, re.IGNORECASE):
        return False
    return bool(re.search(
        r'\buser[-\s]+provided\s+spec\b|'
        r'\bprovided\s+(?:project\s+)?spec\b|'
        r'\bexternal\s+spec\b|'
        r'\bcustomer\s+spec\b',
        text, re.IGNORECASE))


def _infer_level_from_dirs(proj_dir: str) -> str:
    """Infer project complexity from directory structure and RTL artifacts.

    Hardening: RTL file count and multi-protocol signals can override
    directory-only inference.  A missing or weak dev_log Level must not
    downgrade artifact-based L2 evidence.
    """
    has_rtl = os.path.isdir(os.path.join(proj_dir, 'rtl'))
    has_tb = os.path.isdir(os.path.join(proj_dir, 'tb'))

    # Check RTL file count (>= 3 .v/.sv files -> L2)
    if has_rtl:
        rtl_dir = os.path.join(proj_dir, 'rtl')
        rtl_files = [f for f in os.listdir(rtl_dir) if f.endswith(('.v', '.sv'))]
        if len(rtl_files) >= 3:
            print(f"Inferred level: L2 ({len(rtl_files)} RTL files in rtl/)")
            return 'L2'

        # Check for multi-protocol signals
        if rtl_files:
            all_text = ''
            for fname in rtl_files:
                fpath = os.path.join(rtl_dir, fname)
                try:
                    with open(fpath, 'r', encoding='utf-8', errors='replace') as f:
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
                print("Inferred level: L2 (multi-protocol signals detected)")
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
                        print(
                            f"Inferred level: L2 (module '{parent}' instantiates "
                            f">= 2 sub-modules)")
                        return 'L2'

    if has_rtl and has_tb:
        print("Inferred level: L2 (both rtl/ and tb/ directories present)")
        return 'L2'
    if has_rtl:
        print("Inferred level: L1 (rtl/ present, no tb/ directory)")
        return 'L1'

    print("Inferred level: L1 (default, no distinct L2 signals found)")
    return 'L1'


def find_level_and_spec(proj_dir: str) -> tuple[str, bool]:
    """Best-effort detect L0/L1/L2 and user-spec presence.

    Checks docs/dev_log.md (canonical) first, then root dev_log.md.
    Falls back to directory-structure/artifact inference.
    Hardening: artifact-based L2 evidence is never overridden by a silent dev_log.
    """
    level = 'L1'
    has_user_spec = False
    dev_log_found = False
    dev_log_explicit = False

    dev_log_paths = [
        os.path.join(proj_dir, 'docs', 'dev_log.md'),
        os.path.join(proj_dir, 'dev_log.md'),
    ]
    for dev_log in dev_log_paths:
        if os.path.isfile(dev_log):
            dev_log_found = True
            with open(dev_log, 'r', encoding='utf-8', errors='replace') as f:
                text = f.read()

            if re.search(r'\bL2\b', text[:500]):
                level = 'L2'
                dev_log_explicit = True
            elif re.search(r'\bL0\b', text[:500]):
                level = 'L0'
                dev_log_explicit = True

            if _detect_user_spec(text):
                has_user_spec = True

    spec_md = os.path.join(proj_dir, 'docs', 'SPEC.md')
    if os.path.isfile(spec_md):
        with open(spec_md, 'r', encoding='utf-8', errors='replace') as f:
            text = f.read()
        if _detect_user_spec(text):
            has_user_spec = True

    # Always run artifact inference.  If artifacts say L2, never downgrade.
    inferred = _infer_level_from_dirs(proj_dir)
    if inferred == 'L2' and level != 'L2':
        level = 'L2'
        if dev_log_found and not dev_log_explicit:
            print("NOTICE: Artifact-based L2 inference overrides silent dev_log level")
    elif not dev_log_found and inferred != level:
        level = inferred

    return level, has_user_spec


# ---------------------------------------------------------------------------
#  Preflight checks
# ---------------------------------------------------------------------------

def _check_module_target(proj_dir: str) -> list[str]:
    """L0 requires a module target -- a named design target.

    Accepts the first heading in dev_log.md (any level) as a module name, or
    falls back to the project directory name.
    """
    findings = []

    dev_log = os.path.join(proj_dir, 'docs', 'dev_log.md')
    if os.path.isfile(dev_log):
        with open(dev_log, 'r', encoding='utf-8', errors='replace') as f:
            text = f.read()
        # Accept any non-empty heading in the first 1000 chars as module target
        if re.search(r'^#+\s+\S+', text[:1000], re.MULTILINE):
            return findings

    # Fallback: project directory name
    dir_name = os.path.basename(os.path.normpath(proj_dir))
    if re.match(r'^[A-Za-z_][A-Za-z0-9_\-]*$', dir_name):
        return findings

    findings.append(
        "L0: No module target found -- dev_log.md lacks a title heading "
        "and project directory name is not a valid identifier")
    return findings


def check_preflight(proj_dir: str, level: str, has_user_spec: bool) -> list[str]:
    """Return a list of missing skeleton findings.

    For L0:  dev_log.md + module target only.
    For L1/L2 (No-SPEC): directories + skeleton files under docs/.
    """
    findings = []

    # ----- L0 -----------------------------------------------------------------
    if level == 'L0':
        dev_log = os.path.join(proj_dir, 'docs', 'dev_log.md')
        if not os.path.isfile(dev_log):
            findings.append("Missing required artifact: docs/dev_log.md (L0)")
        findings.extend(_check_module_target(proj_dir))
        return findings

    # ----- L1 / L2 -----------------------------------------------------------
    # Directories required per level
    required_dirs = ['docs', 'rtl', 'tb', 'sim']

    for dir_name in required_dirs:
        dir_path = os.path.join(proj_dir, dir_name)
        if not os.path.isdir(dir_path):
            findings.append(f"Missing required directory: {dir_name}/")

    # Skeleton files under docs/ (No-SPEC only; user-provided SPEC projects
    # supply these externally and need only a dev_log placeholder)
    if not has_user_spec:
        skeleton_files = [
            os.path.join('docs', 'dev_log.md'),
            os.path.join('docs', 'SPEC.md'),
            os.path.join('docs', 'interface-contracts.md'),
            os.path.join('docs', 'timing-contract.md'),
            os.path.join('docs', 'protocol_claim_ledger.md'),
            os.path.join('docs', 'verification_matrix.md'),
            os.path.join('docs', 'contract_implementation_matrix.md'),
        ]
        for rel_path in skeleton_files:
            full = os.path.join(proj_dir, rel_path)
            if not os.path.isfile(full):
                findings.append(f"Missing required skeleton file: {rel_path}")

    # Even with a user SPEC, a dev_log is always expected
    if has_user_spec:
        dev_log = os.path.join(proj_dir, 'docs', 'dev_log.md')
        if not os.path.isfile(dev_log):
            findings.append("Missing required artifact: docs/dev_log.md")

    return findings


# ---------------------------------------------------------------------------
#  CLI
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Project preflight gate: verify project skeleton before RTL generation.")
    parser.add_argument('project_dir', help='Project directory to check')
    args = parser.parse_args()

    proj_dir = args.project_dir
    if not os.path.isdir(proj_dir):
        print(f"[REJECT] Not a directory: {proj_dir}", file=sys.stderr)
        sys.exit(1)

    level, has_user_spec = find_level_and_spec(proj_dir)
    print(f"Detected level: {level}, user-spec: {has_user_spec}")

    findings = check_preflight(proj_dir, level, has_user_spec)

    if not findings:
        print("PROJECT_PREFLIGHT_GATE: PASS")
        sys.exit(0)

    print("PROJECT_PREFLIGHT_GATE: FAIL")
    for f in findings:
        print(f"  - {f}")
    sys.exit(1)


if __name__ == '__main__':
    main()
