"""Project artifact gate: verify required L1/L2 project evidence exists.

For an L1/L2 No-SPEC project, require:
  - docs/dev_log.md
  - docs/SPEC.md
  - docs/interface-contracts.md
  - docs/timing-contract.md
  - docs/protocol_claim_ledger.md
  - docs/verification_matrix.md
  - docs/contract_implementation_matrix.md

For an L2 project with "Delegate: yes", require docs/delegation_plan.md and
all role reports under docs/subagents/.

Evidence cross-check: parse docs/protocol_claim_ledger.md,
docs/verification_matrix.md, and docs/contract_implementation_matrix.md for
evidence tokens and require those tokens to appear in a TB file or simulation
log.

L2 per-module simulation gate: require docs/module_verification_matrix.md.
Each RTL module must be listed with module-level simulation/proof evidence or a
clear waiver.

Residual risk gate: Status: PASS cannot coexist with blocking residual-risk
phrases unless the line is explicitly classified as Accepted Limitation and has
waiver/evidence.

Usage: python scripts/project_artifact_gate.py <project_dir>
"""
import argparse
import io
import json
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


def _detect_user_spec(text: str) -> bool:
    """Return True only for affirmative evidence that an external/user SPEC exists."""
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


def _strip_verilog_comments(text: str) -> str:
    """Remove Verilog comments before regex-based structure scans."""
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)
    text = re.sub(r'//.*', '', text)
    return text


def _instantiates_module(text: str, module_name: str) -> bool:
    """Return True if text instantiates a specific RTL module.

    Supports ordinary and parameterized instantiations:
      module_name inst_name (...);
      module_name #(...) inst_name (...);
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


def _infer_level_from_artifacts(proj_dir: str) -> str:
    """Infer project complexity level from artifacts when dev_log is missing.

    Checks RTL file count, protocol signal presence, and testbench/simulation
    infrastructure to distinguish L1 from L2 projects.

    Hardening: artifact-based L2 evidence is never overridden by a silent dev_log.
    A missing or weak dev_log Level must not downgrade L2 signals.
    """
    rtl_dir = os.path.join(proj_dir, 'rtl')
    tb_dir = os.path.join(proj_dir, 'tb')
    sim_dir = os.path.join(proj_dir, 'sim')

    rtl_v_files = []
    if os.path.isdir(rtl_dir):
        rtl_v_files = [f for f in os.listdir(rtl_dir) if f.endswith(('.v', '.sv'))]

    tb_v_files = []
    if os.path.isdir(tb_dir):
        tb_v_files = [f for f in os.listdir(tb_dir) if f.endswith(('.v', '.sv'))]

    # Rule 1: >= 3 .v/.sv files in rtl/ -> L2 (multi-module project)
    if len(rtl_v_files) >= 3:
        print(f"Inferred level: L2 ({len(rtl_v_files)} RTL files in rtl/)")
        return 'L2'

    # Rule 2: top module + >= 2 leaf modules -> L2, even when several
    # modules live in one RTL file.
    if len(rtl_v_files) >= 1:
        all_rtl_text = ''
        for fname in rtl_v_files:
            fpath = os.path.join(rtl_dir, fname)
            with open(fpath, 'r', encoding='utf-8', errors='replace') as f:
                all_rtl_text += f.read() + '\n'
        module_names = re.findall(
            r'^\s*module\s+([A-Za-z_]\w*)\b', all_rtl_text, re.MULTILINE)
        if len(module_names) >= 3:
            module_set = set(module_names)
            for body_m in re.finditer(
                    r'^\s*module\s+([A-Za-z_]\w*)\b(.*?)(?=^\s*endmodule\b)',
                    all_rtl_text, re.MULTILINE | re.DOTALL):
                parent = body_m.group(1)
                body = body_m.group(2)
                instantiated = _find_instantiated_modules(
                    body, {mod for mod in module_set if mod != parent})
                if len(instantiated) >= 2:
                    print(
                        f"Inferred level: L2 (module '{parent}' instantiates "
                        f">= 2 sub-modules)")
                    return 'L2'

    # Rule 3: tb/ with test files + rtl/ with >= 2 .v files -> L2
    if len(tb_v_files) > 0 and len(rtl_v_files) >= 2:
        print(f"Inferred level: L2 (tb/ with {len(tb_v_files)} tests, "
              f"rtl/ with {len(rtl_v_files)} files)")
        return 'L2'

    # Rule 4: multi-protocol signals (NVMe+AXI, DMA+AXI, NAND+AXI) -> L2
    if len(rtl_v_files) > 0:
        all_rtl_text = ''
        for fname in rtl_v_files:
            fpath = os.path.join(rtl_dir, fname)
            with open(fpath, 'r', encoding='utf-8', errors='replace') as f:
                all_rtl_text += f.read() + '\n'

        has_nvme = bool(re.search(
            r'\b(prp1|prp2|slba|nlb|cpl_status)\b', all_rtl_text, re.IGNORECASE))
        has_dma = bool(re.search(
            r'\b(dma|burst_len|transfer_size|descriptor)\b', all_rtl_text, re.IGNORECASE))
        has_nand = bool(re.search(
            r'\b(nand|page_program|page_read|block_erase)\b', all_rtl_text, re.IGNORECASE))
        has_axi = bool(re.search(
            r'\b(m_axi_awvalid|m_axi_wvalid|awaddr|awlen)\b', all_rtl_text, re.IGNORECASE))

        if (has_nvme or has_dma or has_nand) and has_axi:
            print("Inferred level: L2 (multi-protocol signals detected)")
            return 'L2'

    # Rule 5: sim/ with .vvp files -> at least L1 (default)
    if os.path.isdir(sim_dir):
        vvp_files = [f for f in os.listdir(sim_dir) if f.endswith('.vvp')]
        if vvp_files:
            print(f"Inferred level: L1 (sim/ with .vvp simulation output)")

    return 'L1'


def find_level_and_spec(proj_dir: str) -> tuple[str, bool]:
    """Best-effort detect L0/L1/L2 and whether a user SPEC was provided.
    Checks both docs/dev_log.md (canonical) and root dev_log.md.
    When no dev_log is found, infers L2 from multi-module artifacts.
    Hardening: artifact-based L2 evidence is never overridden by a silent dev_log."""
    level = 'L1'  # default assumption
    has_user_spec = False
    dev_log_found = False
    dev_log_explicit = False  # True when dev_log explicitly states L2

    # Check both locations for level and spec detection
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
    inferred = _infer_level_from_artifacts(proj_dir)
    if inferred == 'L2' and level != 'L2':
        level = 'L2'
        if dev_log_found and not dev_log_explicit:
            print("NOTICE: Artifact-based L2 inference overrides silent dev_log level")
    elif not dev_log_found and inferred != level:
        level = inferred

    return level, has_user_spec


def check_artifacts(proj_dir: str, level: str, has_user_spec: bool) -> list[str]:
    """Return list of missing artifact findings."""
    findings = []

    if level == 'L0' and has_user_spec:
        return findings  # L0 with user spec has fewer requirements

    required = [os.path.join('docs', 'dev_log.md')]
    if not has_user_spec:
        required.extend([
            os.path.join('docs', 'SPEC.md'),
            os.path.join('docs', 'interface-contracts.md'),
            os.path.join('docs', 'protocol_claim_ledger.md'),
            os.path.join('docs', 'verification_matrix.md'),
            os.path.join('docs', 'timing-contract.md'),
            os.path.join('docs', 'contract_implementation_matrix.md'),
        ])

    for rel_path in required:
        full = os.path.join(proj_dir, rel_path)
        if not os.path.isfile(full):
            findings.append(f"Missing required artifact: {rel_path}")

    return findings


def _collect_tb_content(proj_dir: str) -> tuple[str, list[str]]:
    """Collect TB file content from canonical tb/ and non-canonical sim/tb_* paths.
    Returns (combined_content, warning_findings)."""
    findings = []

    tb_dir = os.path.join(proj_dir, 'tb')
    tb_content = ''
    tb_found_in_tb = False
    if os.path.isdir(tb_dir):
        for fname in os.listdir(tb_dir):
            if fname.endswith(('.v', '.sv')):
                tb_found_in_tb = True
                fpath = os.path.join(tb_dir, fname)
                with open(fpath, 'r', encoding='utf-8', errors='replace') as f:
                    tb_content += f.read() + '\n'

    sim_dir = os.path.join(proj_dir, 'sim')
    sim_tb_content = ''
    tb_found_in_sim = False
    if os.path.isdir(sim_dir):
        for fname in os.listdir(sim_dir):
            if fname.startswith('tb_') and fname.endswith(('.v', '.sv')):
                tb_found_in_sim = True
                fpath = os.path.join(sim_dir, fname)
                with open(fpath, 'r', encoding='utf-8', errors='replace') as f:
                    sim_tb_content += f.read() + '\n'

    if tb_found_in_sim and not tb_found_in_tb:
        findings.append(
            "Non-canonical: TB files found under sim/ not tb/. "
            "Evidence cross-ref checked sim/ but recommend canonical tb/ placement.")

    return tb_content + '\n' + sim_tb_content, findings


def _collect_tb_and_sim_content(proj_dir: str) -> tuple[str, list[str]]:
    """Collect TB source plus text logs from sim/ for evidence matching."""
    content, findings = _collect_tb_content(proj_dir)
    sim_dir = os.path.join(proj_dir, 'sim')
    if os.path.isdir(sim_dir):
        for root, _, files in os.walk(sim_dir):
            for fname in files:
                if fname.endswith(('.log', '.out', '.txt')):
                    fpath = os.path.join(root, fname)
                    try:
                        with open(fpath, 'r', encoding='utf-8', errors='replace') as f:
                            content += '\n' + f.read()
                    except OSError:
                        findings.append(f"Cannot read sim evidence log: {fpath}")
    return content, findings


def _read_file(path: str) -> str:
    if not os.path.isfile(path):
        return ''
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        return f.read()


def _project_claims_pass(proj_dir: str) -> bool:
    """Detect PASS claims from all project artifacts, not just dev_log.

    Checks dev_log, verification_matrix, project_summary, root summary,
    and sim/*.log for ALL_TESTS_PASS, SIMULATION_DONE, or Status: PASS.
    This ensures protocol_claim_ledger TBD rows fail when verification_matrix
    claims ALL_TESTS_PASS even if dev_log does not explicitly say PASS.
    """
    # 1. dev_log (canonical + root fallback)
    text = (
        _read_file(os.path.join(proj_dir, 'docs', 'dev_log.md')) + '\n' +
        _read_file(os.path.join(proj_dir, 'dev_log.md'))
    )
    if re.search(
        r'\bStatus:\s*(PASS|COMPLETE)\b|\bALL_TESTS_PASS\b|'
        r'\bFinal\s+Status\b.*\bPASS\b',
        text, re.IGNORECASE | re.DOTALL):
        return True

    # 2. verification_matrix.md or project_summary.md
    for doc in ('verification_matrix.md', 'project_summary.md'):
        doc_text = _read_file(os.path.join(proj_dir, 'docs', doc))
        if re.search(r'\bALL_TESTS_PASS\b|\bSIMULATION_DONE\b|\bStatus:\s*PASS\b',
                     doc_text, re.IGNORECASE):
            return True

    # 3. Root-level summary files
    for root_doc in ('summary.md', 'project_summary.md', 'README.md'):
        root_text = _read_file(os.path.join(proj_dir, root_doc))
        if re.search(r'\bALL_TESTS_PASS\b|\bSIMULATION_DONE\b|\bStatus:\s*PASS\b',
                     root_text, re.IGNORECASE):
            return True

    # 4. sim/*.log for ALL_TESTS_PASS or SIMULATION_DONE markers
    sim_dir = os.path.join(proj_dir, 'sim')
    if os.path.isdir(sim_dir):
        for fname in os.listdir(sim_dir):
            if fname.endswith(('.log', '.out')):
                log_text = _read_file(os.path.join(sim_dir, fname))
                if re.search(r'\bALL_TESTS_PASS\b|\bSIMULATION_DONE\b',
                             log_text, re.IGNORECASE):
                    return True

    return False


def check_evidence_cross_ref(proj_dir: str) -> list[str]:
    """Parse claim ledger for T<number> evidence tokens and verify they exist in TB files.
    Also cross-check verification_matrix.md test references against TB content."""
    findings = []
    ledger_path = os.path.join(proj_dir, 'docs', 'protocol_claim_ledger.md')
    if not os.path.isfile(ledger_path):
        return findings  # already reported as missing

    with open(ledger_path, 'r', encoding='utf-8', errors='replace') as f:
        ledger_text = f.read()

    # Extract evidence tokens like T1, T10, T2a etc.
    evidence_tokens = set(re.findall(r'\bT(\d+[a-zA-Z]?)\b', ledger_text))
    if not evidence_tokens:
        return findings

    combined_content, tb_warnings = _collect_tb_and_sim_content(proj_dir)
    findings.extend(tb_warnings)

    for token in sorted(evidence_tokens, key=lambda x: (len(x), x)):
        pattern = rf'\bT{re.escape(token)}\b'
        if not re.search(pattern, combined_content):
            findings.append(
                f"Evidence token T{token} cited in claim ledger but not found "
                f"in any TB file or simulation log under tb/ or sim/")

    return findings


def check_verification_matrix_evidence(proj_dir: str) -> list[str]:
    """Cross-check verification/contract/claim test references against evidence.

    Parses verification_matrix.md, contract_implementation_matrix.md, and
    protocol_claim_ledger.md for test IDs/names. Verifies each evidence token
    appears in TB source or sim logs. Catches matrix rows that remain Pending
    while the dev log claims PASS.

    Strengthened: matrix entries must bind to actual TB tasks/markers and sim
    log markers.  Mere mentions inside docs are not evidence.  If a matrix item
    is planned but not run, require NOT_RUN or WAIVED and prevent final PASS
    unless accepted limitation is explicit.
    """
    findings = []
    docs_dir = os.path.join(proj_dir, 'docs')
    doc_names = [
        'verification_matrix.md',
        'contract_implementation_matrix.md',
        'protocol_claim_ledger.md',
    ]
    doc_texts = {}
    for doc_name in doc_names:
        doc_texts[doc_name] = _read_file(os.path.join(docs_dir, doc_name))

    matrix_text = doc_texts['verification_matrix.md']
    if not any(doc_texts.values()):
        return findings  # missing docs are reported elsewhere

    if matrix_text and _project_claims_pass(proj_dir):
        for i, line in enumerate(matrix_text.splitlines(), 1):
            if '|' not in line:
                continue
            if re.match(r'^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$',
                        line):
                continue
            cells = [cell.strip() for cell in line.strip().strip('|').split('|')]
            has_placeholder = any(
                re.search(r'\b(Pending|TBD|TODO|Waiver\s*Pending|NOT_RUN)\b',
                          cell, re.IGNORECASE) or cell in ('', '-', '--')
                for cell in cells
            )
            if has_placeholder:
                # Check if this is an explicit accepted limitation
                row_text = ' '.join(cells)
                is_accepted = bool(re.search(
                    r'\b(Accepted\s+Limitation|waived|NOT_RUN)\b',
                    row_text, re.IGNORECASE))
                if is_accepted:
                    continue  # Explicit accepted limitation is OK
                findings.append(
                    f"verification_matrix.md line {i} remains Pending/TBD/blank/NOT_RUN "
                    "while project claims PASS. Mark as Accepted Limitation or WAIVED "
                    "if intentional.")
                continue

    # Extract test references:
    # - table row IDs like | T1 |, | F01 |, | P04 |
    # - TB: evidence tokens
    # - TEST_PASS/TEST_START/TEST_FAIL <name>
    # - check_<name> and test_<name> identifiers
    test_names = set()
    all_doc_text = '\n'.join(doc_texts.values())
    for line in all_doc_text.splitlines():
        if '|' in line:
            # P1/P2/etc. are often design-principle IDs, not verification
            # test IDs.  Treat P-series matrix IDs as tests only when they use
            # at least two digits, e.g. P04/P09.
            for m in re.finditer(
                    r'\b([TFBDCE]\d+[A-Za-z]?|P\d{2,}[A-Za-z]?)\b',
                    line):
                test_names.add(m.group(1))
        for m in re.finditer(r'\bTB:\s*([A-Za-z_]\w*|[TFPBDCE]\d+[A-Za-z]?)', line):
            test_names.add(m.group(1))
        for m in re.finditer(r'TEST_(?:PASS|START|FAIL)\s+(\w+)', line):
            test_names.add(m.group(1))
        for m in re.finditer(r'\b(check_\w+)', line):
            test_names.add(m.group(1))
        for m in re.finditer(r'\b(test_\w+)', line):
            name = m.group(1)
            if name not in ('test_id', 'test_count', 'test_cnt', 'test_num',
                            'test_err', 'test_pass', 'test_fail'):
                test_names.add(name)

    if not test_names:
        return findings

    # Collect TB source and sim logs separately for evidence classification
    tb_content, tb_warnings = _collect_tb_content(proj_dir)
    combined_content, _ = _collect_tb_and_sim_content(proj_dir)
    findings.extend(tb_warnings)

    for name in sorted(test_names):
        # Check TB source first (stronger evidence than doc mention)
        in_tb = bool(re.search(r'\b' + re.escape(name) + r'\b', tb_content))
        # Check sim logs (TEST_PASS/TEST_FAIL markers)
        sim_dir = os.path.join(proj_dir, 'sim')
        in_sim_log = False
        if os.path.isdir(sim_dir):
            for fname in os.listdir(sim_dir):
                if fname.endswith('.log'):
                    log_text = _read_file(os.path.join(sim_dir, fname))
                    if re.search(r'\b' + re.escape(name) + r'\b', log_text):
                        in_sim_log = True
                        break

        if not in_tb and not in_sim_log:
            # Only mention in docs -- not real evidence
            in_docs_only = bool(re.search(r'\b' + re.escape(name) + r'\b', all_doc_text))
            if in_docs_only:
                findings.append(
                    f"Evidence token '{name}' found only in docs, not in TB files "
                    f"or simulation logs. Doc mentions are not execution evidence.")
            else:
                findings.append(
                    f"Contract/test evidence references '{name}' but it was not found "
                    f"in any TB file or simulation log under tb/ or sim/")

    return findings


def _parse_rtl_modules(proj_dir: str) -> dict[str, int]:
    """Return module name -> line count for rtl/*.v files."""
    modules = {}
    rtl_dir = os.path.join(proj_dir, 'rtl')
    if not os.path.isdir(rtl_dir):
        return modules
    for fname in os.listdir(rtl_dir):
        if not fname.endswith(('.v', '.sv')):
            continue
        fpath = os.path.join(rtl_dir, fname)
        text = _read_file(fpath)
        line_count = len(text.splitlines())
        for m in re.finditer(r'^\s*module\s+([A-Za-z_]\w*)\b', text, re.MULTILINE):
            modules[m.group(1)] = line_count
    return modules


def _parse_rtl_module_sources(proj_dir: str) -> dict[str, str]:
    """Return module name -> containing RTL file text for rtl/*.v files."""
    modules = {}
    rtl_dir = os.path.join(proj_dir, 'rtl')
    if not os.path.isdir(rtl_dir):
        return modules
    for fname in os.listdir(rtl_dir):
        if not fname.endswith(('.v', '.sv')):
            continue
        fpath = os.path.join(rtl_dir, fname)
        text = _read_file(fpath)
        for m in re.finditer(r'^\s*module\s+([A-Za-z_]\w*)\b', text, re.MULTILINE):
            modules[m.group(1)] = text
    return modules


def _find_top_modules(module_sources: dict[str, str]) -> set[str]:
    """Identify top/wrapper modules that instantiate other RTL modules."""
    module_names = set(module_sources.keys())
    top_modules: set[str] = set()
    for mod_name, text in module_sources.items():
        instantiated = _find_instantiated_modules(
            text, {m for m in module_names if m != mod_name})
        wrapper_named = bool(re.search(
            r'(top|wrapper|integrat|subsystem|system)', mod_name, re.IGNORECASE))
        if len(instantiated) >= 2 or (instantiated and wrapper_named):
            top_modules.add(mod_name)
    return top_modules


def _log_has_pass_evidence(text: str) -> bool:
    return bool(
        ('ALL_TESTS_PASS' in text and 'SIMULATION_DONE' in text) or
        re.search(r'\b(SIM_LOG_GATE|COMPILE_LOG_GATE|FORMAL|ASSERT).*\bPASS\b',
                  text, re.IGNORECASE))


def _extract_evidence_paths(line: str) -> list[str]:
    paths = []
    for m in re.finditer(
            r'((?:sim|logs|formal|out|build)[/\\][^|\s,;]+?\.(?:log|out|txt))',
            line, re.IGNORECASE):
        paths.append(m.group(1).strip('`"\''))
    return paths


def check_module_verification_evidence(proj_dir: str, level: str) -> list[str]:
    """L2 gate: each RTL module needs module-level evidence or waiver."""
    findings = []
    if level != 'L2':
        return findings

    matrix_path = os.path.join(proj_dir, 'docs', 'module_verification_matrix.md')
    if not os.path.isfile(matrix_path):
        findings.append(
            "Missing required artifact: docs/module_verification_matrix.md "
            "(L2 per-module simulation gate)")
        return findings

    matrix_text = _read_file(matrix_path)
    modules = _parse_rtl_modules(proj_dir)
    if not modules:
        return findings
    top_modules = _find_top_modules(_parse_rtl_module_sources(proj_dir))

    for module_name, line_count in sorted(modules.items()):
        if module_name in top_modules:
            continue
        rows = [
            line for line in matrix_text.splitlines()
            if re.search(r'\b' + re.escape(module_name) + r'\b', line)
        ]
        if not rows:
            findings.append(
                f"Module '{module_name}' missing from docs/module_verification_matrix.md")
            continue

        row_text = '\n'.join(rows)
        has_waiver = bool(re.search(
            r'\b(waiver|waived|integration[-\s]?only|top[-\s]?level|'
            r'top\s+wrapper|trivial)\b',
            row_text, re.IGNORECASE))
        if has_waiver:
            continue

        paths = []
        for row in rows:
            paths.extend(_extract_evidence_paths(row))
        if not paths:
            findings.append(
                f"Module '{module_name}' lacks module-level sim/proof log "
                "evidence or waiver in docs/module_verification_matrix.md")
            continue

        any_pass = False
        for rel_path in paths:
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
                findings.append(f"Module '{module_name}' evidence path escapes project: {rel_path}")
                continue
            if not os.path.isfile(full_path):
                findings.append(
                    f"Module '{module_name}' evidence log not found: {rel_path}")
                continue
            if _log_has_pass_evidence(_read_file(full_path)):
                any_pass = True
        if not any_pass:
            findings.append(
                f"Module '{module_name}' has no PASS evidence in referenced "
                "module-level logs")

    return findings


def _check_role_report_provenance(role_path: str, role_file: str) -> list[str]:
    """Validate provenance fields in a subagent role report.

    Required fields: Role, Scope, Input contract(s), Evidence source or
    invocation/session, Acceptance commands, Findings/decision.
    Delegate: yes without provenance = FAIL.
    """
    findings = []
    text = _read_file(role_path)
    if not text.strip():
        findings.append(
            f"Role report docs/subagents/{role_file} is empty; "
            f"Delegate: yes requires provenance fields in each role report")
        return findings

    required_fields = [
        (r'\bRole\b', 'Role'),
        (r'\bScope\b', 'Scope'),
        (r'\bInput\s+contract', 'Input contract(s)'),
        (r'\b(Evidence\s+source|Invocation|Session)\b', 'Evidence source/invocation'),
        (r'\bAcceptance\s+command', 'Acceptance commands'),
        (r'\b(Findings|Decision)\b', 'Findings/decision'),
    ]

    for pattern, field_name in required_fields:
        if not re.search(pattern, text, re.IGNORECASE):
            findings.append(
                f"Role report docs/subagents/{role_file} missing "
                f"required provenance field: {field_name}")

    return findings


def check_delegation_evidence(proj_dir: str, level: str) -> list[str]:
    """L2 Delegation Evidence Gate: verify delegation artifacts with provenance.

    For L2 projects, parse dev_log for 'Delegate: yes' or 'Delegate: no'.
    - Delegate: yes requires docs/delegation_plan.md + all role reports under
      docs/subagents/ with provenance fields (Role, Scope, Input contract,
      Evidence source, Acceptance commands, Findings/decision).
    - Delegate: no requires waiver record and compensation gates evidence.
    - No delegation decision found = FAIL.
    L0/L1 delegation = no subagent artifacts required.
    """
    findings = []

    if level != 'L2':
        return findings  # L0/L1 = no subagent artifacts required

    # Read dev_log (canonical first, fallback to root)
    dev_log = os.path.join(proj_dir, 'docs', 'dev_log.md')
    if not os.path.isfile(dev_log):
        dev_log = os.path.join(proj_dir, 'dev_log.md')

    text = ''
    if os.path.isfile(dev_log):
        with open(dev_log, 'r', encoding='utf-8', errors='replace') as f:
            text = f.read()

    # Search for delegation decision (case insensitive, supports Markdown bold)
    delegate_match = re.search(r'\*?\*?Delegate:\*?\*?\s*(yes|no)', text, re.IGNORECASE)
    decision = None
    if delegate_match:
        decision = delegate_match.group(1).lower()
    else:
        # Check for alternative "Delegation Decision" format
        delegation_decision_match = re.search(
            r'Delegation\s+Decision\s*:\s*(.*?)(?:\n|$)', text, re.IGNORECASE)
        if delegation_decision_match:
            dec_text = delegation_decision_match.group(1).strip().lower()
            if 'no delegation' in dec_text or dec_text == 'no':
                print("NOTICE: 'Delegation Decision: No delegation' found instead of canonical "
                      "'Delegate: yes/no' format. Treating as 'Delegate: no'. "
                      "Recommend canonical format 'Delegate: yes' or 'Delegate: no'.")
                decision = 'no'

    if decision is None:
        findings.append(
            "L2: No delegation decision found in dev_log "
            "(require 'Delegate: yes' or 'Delegate: no')")
        return findings

    if decision == 'yes':
        # Require delegation plan
        plan_path = os.path.join(proj_dir, 'docs', 'delegation_plan.md')
        if not os.path.isfile(plan_path):
            findings.append(
                "Missing required artifact: docs/delegation_plan.md (L2 Delegate: yes)")

        # Require all role reports under docs/subagents/ with provenance
        required_roles = [
            'architect.md',
            'protocol_reviewer.md',
            'axi_transaction_reviewer.md',
            'rtl_structural_reviewer.md',
            'verification_reviewer.md',
            'integration_reviewer.md',
        ]
        subagents_dir = os.path.join(proj_dir, 'docs', 'subagents')
        for role_file in required_roles:
            role_path = os.path.join(subagents_dir, role_file)
            if not os.path.isfile(role_path):
                findings.append(
                    f"Missing required role report: docs/subagents/{role_file} "
                    f"(L2 Delegate: yes)")
            else:
                # Validate provenance fields in the role report
                findings.extend(_check_role_report_provenance(role_path, role_file))

    elif decision == 'no':
        # Require waiver and compensation gates evidence in dev_log
        if not re.search(r'\bwaiver\b', text, re.IGNORECASE):
            findings.append(
                "L2 Delegate: no but no waiver record found in dev_log")

        if not re.search(r'\bcompensation\s*gates?\b', text, re.IGNORECASE):
            findings.append(
                "L2 Delegate: no but no compensation gates checked in dev_log")

    return findings


def check_residual_risks(proj_dir: str) -> list[str]:
    """Residual Risk Gate: detect blocking phrases in residual risks section.

    Parse dev_log for a residual risks section. If Status: PASS is found
    anywhere in the file AND the residual risks section contains blocking
    phrases, report FAIL -- unless the phrase is explicitly classified as
    'Accepted Limitation' with waiver/evidence.
    """
    findings = []

    dev_log = os.path.join(proj_dir, 'docs', 'dev_log.md')
    if not os.path.isfile(dev_log):
        dev_log = os.path.join(proj_dir, 'dev_log.md')

    if not os.path.isfile(dev_log):
        return findings

    with open(dev_log, 'r', encoding='utf-8', errors='replace') as f:
        text = f.read()

    # If no Status: line found at all, skip this check
    if not re.search(r'Status:', text):
        return findings

    # Only flag if Status: PASS is found
    if not re.search(r'Status:\s*PASS', text, re.IGNORECASE):
        return findings

    # Find the Residual Risks section (any heading depth)
    section_match = re.search(
        r'^#{1,6}\s+Residual\s+Risks?\s*$(.+?)(?=^#{1,6}\s|\Z)',
        text, re.IGNORECASE | re.MULTILINE | re.DOTALL)
    if not section_match:
        return findings  # No residual risks section, nothing to check

    residual_text = section_match.group(1)

    # Blocking phrases that contradict a PASS status
    blocking_patterns = [
        r'No\s+.*testing',
        r'not implemented',
        r'tied off',
        r'simplified',
        r'NOT supported',
        r'unverified',
        r'missing',
        r'not fully',
        r'stub',
    ]

    for line in residual_text.split('\n'):
        line_stripped = line.strip()
        if not line_stripped:
            continue
        for pattern in blocking_patterns:
            if re.search(pattern, line_stripped, re.IGNORECASE):
                # Skip only if classified as Accepted Limitation AND backed by
                # waiver/evidence. A bare "waiver" word is not enough.
                has_accepted = re.search(
                    r'Accepted Limitation', line_stripped, re.IGNORECASE)
                has_evidence = re.search(
                    r'\b(waiver|waived|evidence|contract_implementation_matrix|'
                    r'T\d+|negative\s+test)\b',
                    line_stripped, re.IGNORECASE)
                if has_accepted and has_evidence:
                    continue
                findings.append(
                    f"Residual risk blocking phrase '{pattern}' found "
                    f"(line: {line_stripped[:120]}). Classify as "
                    f"Accepted Limitation with waiver/evidence or keep Status != PASS.")

    return findings


def check_scoreboard_substance(proj_dir: str) -> list[str]:
    """Scoreboard Substance Gate: reject signal-name mentions as scoreboard evidence.

    For DMA/NVMe projects, if TB files mention AWADDR/AWLEN/WLAST/WSTRB/BRESP,
    there must be actual comparison logic (expected model, capture, comparison,
    error counter, or assertion).  Mere $display of signal values is not enough.
    """
    findings = []

    tb_content, tb_warnings = _collect_tb_content(proj_dir)
    if not tb_content.strip():
        return findings

    # Only check DMA/NVMe context
    if not re.search(r'(axi|nvme|dma|m_axi|awaddr|awlen|wstrb|wlast|bresp)',
                     tb_content, re.IGNORECASE):
        return findings

    # Check for transaction-shape signals mentioned but not compared
    shape_signals = {
        'AWADDR': r'\b(?:m_axi_awaddr|awaddr|aw_addr)\b',
        'AWLEN': r'\b(?:m_axi_awlen|awlen|aw_len)\b',
        'WSTRB': r'\b(?:m_axi_wstrb|wstrb)\b',
        'WLAST': r'\b(?:m_axi_wlast|wlast)\b',
        'BRESP': r'\b(?:m_axi_bresp|bresp)\b',
    }

    for sig_name, sig_pattern in shape_signals.items():
        if not re.search(sig_pattern, tb_content, re.IGNORECASE):
            continue
        # Signal is mentioned -- check for real comparison logic
        has_comparison = re.search(
            sig_pattern + r'\s*(?:==|===|!=|!==)', tb_content, re.IGNORECASE)
        has_check_task = re.search(
            r'check_\w+[^;]*' + sig_pattern, tb_content, re.IGNORECASE)
        has_expected = re.search(
            r'(?:expected|exp)_\w*' + sig_pattern, tb_content, re.IGNORECASE)
        has_assertion = re.search(
            r'\bassert\b[^;]*' + sig_pattern, tb_content, re.IGNORECASE)

        if not (has_comparison or has_check_task or has_expected or has_assertion):
            findings.append(
                f"Scoreboard substance: {sig_name} appears in TB but has no "
                f"comparison against expected value (no ==, check_task, expected_*, "
                f"or assert). Signal mention alone is not scoreboard evidence.")

    return findings


def check_prp_feature_claims(proj_dir: str) -> list[str]:
    """Protocol Feature Claim Gate: verify PRP list support claims.

    If docs or RTL claim PRP list support, require an actual PRP list
    fetch/load path or an explicit blocking gap/accepted limitation.
    Detect: list_mem declarations without load/write/fetch interface,
    PRP1 non-zero offset claim while RTL rejects nonzero PRP1 offset.
    """
    findings = []

    rtl_dir = os.path.join(proj_dir, 'rtl')
    if not os.path.isdir(rtl_dir):
        return findings

    all_rtl_text = ''
    for fname in os.listdir(rtl_dir):
        if fname.endswith(('.v', '.sv')):
            all_rtl_text += _read_file(os.path.join(rtl_dir, fname)) + '\n'

    if not re.search(r'\bprp\b', all_rtl_text, re.IGNORECASE):
        return findings  # Not a PRP context

    # Check for list_mem declarations without any load/write/fetch interface
    has_list_mem = re.search(
        r'\b(?:reg|logic)\s+(?:\[[^\]]*\]\s+)*\w*list\w*\s*\[', all_rtl_text, re.IGNORECASE)
    if has_list_mem:
        # Check for actual load/write/fetch of list entries.  A declaration
        # or read such as "list_mem[idx]" is not evidence that entries are
        # populated; require an assignment to the list memory or an explicit
        # write/load/fetch interface.
        list_write_pat = re.compile(
            r'\b\w*list\w*\s*\[[^\]]+\]\s*(?:<=|=)', re.IGNORECASE)
        list_if_pat = re.compile(
            r'\b\w*list\w*(?:_wr|_write|_load|_fetch|_valid|_data_i)\b',
            re.IGNORECASE)
        has_list_load = bool(list_write_pat.search(all_rtl_text))
        has_list_wr = bool(list_if_pat.search(all_rtl_text))
        has_ar_channel = re.search(
            r'\b\w*arvalid\w*\b', all_rtl_text, re.IGNORECASE)

        if has_list_mem and not (has_list_load or has_list_wr or has_ar_channel):
            findings.append(
                "PRP feature claim: list_mem declaration found but no "
                "load/write/fetch interface or AR channel. "
                "PRP list entries cannot be populated. "
                "Mark as Blocking Gap or implement list fetch path.")

    # Check for PRP1 non-zero offset claim while RTL rejects it
    docs_dir = os.path.join(proj_dir, 'docs')
    docs_text = ''
    for doc_name in ['SPEC.md', 'dev_log.md', 'protocol_claim_ledger.md']:
        docs_text += _read_file(os.path.join(docs_dir, doc_name)) + '\n'

    claims_prp1_offset = bool(re.search(
        r'\bPRP1\b.*\b(non-zero|nonzero|offset)\b', docs_text, re.IGNORECASE))
    if claims_prp1_offset:
        # Check if RTL actually handles non-zero PRP1 offset
        has_prp1_offset_logic = bool(re.search(
            r'\b(prp1_\w*(?:offset|mask|base)|'
            r'(?:offset|mask|base)_\w*prp1|'
            r'prp1_i\s*\[\s*11\s*:\s*0\s*\])',
            all_rtl_text, re.IGNORECASE))
        rejects_nonzero = bool(re.search(
            r'\b(prp1\w*aligned|prp1\w*valid)\b.*(?:\?|:|&&|\|\|)|'
            r'\bprp1\w*\s*(?:!=|!==)\s*0\b.*\berror\b',
            all_rtl_text, re.IGNORECASE))
        if not has_prp1_offset_logic or rejects_nonzero:
            findings.append(
                "PRP feature claim: docs claim PRP1 non-zero offset support "
                "but RTL has no usable PRP1 offset handling, or rejects "
                "non-zero PRP1 offsets. "
                "Implement PRP1 offset handling or mark as Accepted Limitation.")

    return findings


def check_protocol_claim_ledger_evidence(proj_dir: str) -> list[str]:
    """Protocol Claim Ledger Evidence Gate: reject TBD/blank Evidence entries.

    For L1/L2 projects claiming PASS, every row in protocol_claim_ledger.md
    must have non-empty, non-TBD Evidence.  Evidence must bind to real TB
    files or simulation logs, not just doc cross-references.
    """
    findings = []

    if not _project_claims_pass(proj_dir):
        return findings

    ledger_path = os.path.join(proj_dir, 'docs', 'protocol_claim_ledger.md')
    if not os.path.isfile(ledger_path):
        return findings  # missing file reported elsewhere

    with open(ledger_path, 'r', encoding='utf-8', errors='replace') as f:
        ledger_text = f.read()

    combined_content, tb_warnings = _collect_tb_and_sim_content(proj_dir)

    for i, line in enumerate(ledger_text.splitlines(), 1):
        if '|' not in line:
            continue
        if re.match(r'^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$', line):
            continue  # table separator
        if re.match(r'^\s*\|?\s*#\s*\|', line):
            continue  # header row

        cells = [cell.strip() for cell in line.strip().strip('|').split('|')]
        if len(cells) < 7:
            continue  # not a full claim row

        evidence_cell = cells[6] if len(cells) > 6 else ''
        claim_cell = cells[1] if len(cells) > 1 else ''

        # Check for TBD/blank/TBD-like evidence
        if not evidence_cell or evidence_cell in ('', '-', '--', 'TBD', 'TBD.', 'tbd'):
            findings.append(
                f"protocol_claim_ledger.md line {i}: Evidence is blank/TBD "
                f"while project claims PASS. Claim: '{claim_cell[:80]}'. "
                f"Provide TB/sim evidence or classify as Accepted Limitation.")
            continue

        # Check for generic placeholders that are not real evidence
        if re.match(r'^(TBD|TODO|pending|to\s+be\s+filled|N/A|none|see\s+dev_log)',
                    evidence_cell, re.IGNORECASE):
            findings.append(
                f"protocol_claim_ledger.md line {i}: Evidence is placeholder "
                f"'{evidence_cell[:40]}' while project claims PASS. "
                f"Provide TB/sim evidence or classify as Accepted Limitation.")

    return findings


def check_storage_mover_evidence(proj_dir: str) -> list[str]:
    """Storage Mover Evidence Gate: require specific TB checks for DMA/NVMe claims.

    When docs or RTL mention storage-mover features, require corresponding
    TB evidence:
    - WSTRB/unaligned claims need TB comparing wstrb/expected_wstrb.
    - RRESP/RD error propagation need TB/log evidence beyond BRESP only.
    - Completion bytes (cpl_bytes/completion bytes) need checking when in interface.
    - PRP list support needs public interface exercise (list_buf_wr_en/list_buf_idx/
      list_buf_data handshake or real fetch), not just hierarchical dut.* writes.
    - Reject docs claiming T10/T11/WSTRB/shape coverage when markers absent.
    """
    findings = []

    rtl_dir = os.path.join(proj_dir, 'rtl')
    if not os.path.isdir(rtl_dir):
        return findings

    # Collect RTL context
    all_rtl_text = ''
    for fname in os.listdir(rtl_dir):
        if fname.endswith(('.v', '.sv')):
            all_rtl_text += _read_file(os.path.join(rtl_dir, fname)) + '\n'

    # Collect doc context
    docs_dir = os.path.join(proj_dir, 'docs')
    all_doc_text = ''
    for doc_name in ['verification_matrix.md', 'dev_log.md', 'SPEC.md',
                      'protocol_claim_ledger.md', 'interface-contracts.md']:
        all_doc_text += _read_file(os.path.join(docs_dir, doc_name)) + '\n'

    # Collect TB + sim evidence
    combined_content, tb_warnings = _collect_tb_and_sim_content(proj_dir)

    # --- WSTRB / unaligned support claims ---
    rtl_has_wstrb = bool(re.search(
        r'\b(?:wstrb|w_strb|m_axi_wstrb)\b', all_rtl_text, re.IGNORECASE))
    doc_claims_unaligned = bool(re.search(
        r'\b(?:unaligned|WSTRB|wstrb|byte.enable|strobe)\b', all_doc_text, re.IGNORECASE))

    if rtl_has_wstrb or doc_claims_unaligned:
        tb_has_wstrb_check = bool(re.search(
            r'\b(?:expected_wstrb|exp_wstrb|wstrb_check|check.*wstrb|'
            r'wstrb\s*(?:===|==|!==|!=))\b',
            combined_content, re.IGNORECASE))
        if not tb_has_wstrb_check:
            findings.append(
                "Storage mover evidence: WSTRB/unaligned support is claimed "
                "or implied but TB has no expected_wstrb/wstrb comparison check. "
                "Add WSTRB verification to testbench or document as Accepted Limitation.")

    # --- RRESP / RD error propagation ---
    rtl_has_rresp = bool(re.search(
        r'\b(?:rresp|r_resp|m_axi_rresp)\b', all_rtl_text, re.IGNORECASE))
    doc_claims_rd_error = bool(re.search(
        r'\b(?:RRESP|read.error|RD.error|response.propagat|rresp)\b',
        all_doc_text, re.IGNORECASE))

    if rtl_has_rresp and doc_claims_rd_error:
        tb_has_rresp_check = bool(re.search(
            r'\b(?:rresp\s*(?:===|==|!==|!=)|check.*rresp|rresp.*error|'
            r'expected_rresp|exp_rresp)\b',
            combined_content, re.IGNORECASE))
        if not tb_has_rresp_check:
            findings.append(
                "Storage mover evidence: RRESP/RD error propagation is claimed "
                "but TB has no RRESP comparison check. "
                "Add RRESP verification to testbench or document as Accepted Limitation.")

    # --- Completion byte counter ---
    rtl_has_cpl_bytes = bool(re.search(
        r'\b(?:cpl_bytes|completion.bytes|cpl_byte_cnt|bytes_written)\b',
        all_rtl_text, re.IGNORECASE))
    doc_claims_cpl_bytes = bool(re.search(
        r'\b(?:cpl_bytes|completion.bytes|bytes.transferred|bytes.written)\b',
        all_doc_text, re.IGNORECASE))

    if rtl_has_cpl_bytes or doc_claims_cpl_bytes:
        tb_has_cpl_check = bool(re.search(
            r'\b(?:cpl_bytes\s*(?:===|==|!==|!=)|check.*cpl_bytes|'
            r'expected_cpl|exp_cpl|cpl_bytes.*expected)\b',
            combined_content, re.IGNORECASE))
        if not tb_has_cpl_check:
            findings.append(
                "Storage mover evidence: completion byte counter (cpl_bytes) "
                "exists but TB has no cpl_bytes comparison check. "
                "Add completion byte verification or document as Accepted Limitation.")

    # --- PRP list public interface exercise ---
    rtl_has_list_buf = bool(re.search(
        r'\b(?:list_buf|list_mem|prp_list)\b', all_rtl_text, re.IGNORECASE))
    doc_claims_prp_list = bool(re.search(
        r'\b(?:PRP.list|prp_list|list.pointer|PRP2.*list)\b',
        all_doc_text, re.IGNORECASE))

    if rtl_has_list_buf or doc_claims_prp_list:
        # Public interface exercise requires ACTIVE write/fetch stimulus,
        # not just signal declarations or reset assignments like
        # list_buf_wr_en = 0.  Accept:
        #   list_buf_wr_en = 1 / <= 1 / <= 1'b1 (active write)
        #   prp_list_wr = 1 / <= 1 (active write)
        #   list_fetch / list_load as transaction verbs
        #   check task explicitly named for public list load
        tb_has_active_list_stimulus = bool(re.search(
            r'\b(?:list_buf_wr_en|prp_list_wr)\s*(?:<=|=\s*)\s*1\b|'
            r'\b(?:list_buf_wr_en|prp_list_wr)\s*(?:<=|=\s*)\s*1\'b1\b|'
            r'\blist_buf_data\s*(?:<=|=\s*)\s*(?!0\b)\S|'
            r'\b(?:list_fetch|list_load)\s*\(',
            combined_content, re.IGNORECASE))
        # A check task explicitly named for public list load
        tb_has_list_check_task = bool(re.search(
            r'\bcheck_\w*list\w*\b|\btest_\w*list\w*load\w*\b|'
            r'\btest_\w*list\w*fetch\w*\b',
            combined_content, re.IGNORECASE))
        # Hierarchical dut.* writes are NOT public interface exercise
        tb_has_hierarchical = bool(re.search(
            r'\bdut(?:\.\w+)*\.\w*(?:list_buf|list_mem)\w*(?:\s*\[|\b)',
            combined_content, re.IGNORECASE))
        # Signal declarations/reset assignments (e.g. list_buf_wr_en = 0)
        tb_has_declaration_only = bool(re.search(
            r'\b(?:list_buf_wr_en|list_buf_idx|list_buf_data|'
            r'prp_list_wr|prp_list_rd)\b',
            combined_content, re.IGNORECASE))

        if not (tb_has_active_list_stimulus or tb_has_list_check_task):
            if tb_has_hierarchical:
                findings.append(
                    "Storage mover evidence: PRP list support claimed but TB "
                    "only uses hierarchical dut.* writes. Public interface "
                    "exercise requires active list_buf_wr_en=1/list_buf_data "
                    "stimulus or a named list-load check task. "
                    "Add PRP list public interface test or document as Accepted Limitation.")
            elif tb_has_declaration_only:
                findings.append(
                    "Storage mover evidence: PRP list support claimed but TB "
                    "only has signal declarations/reset assignments (e.g. "
                    "list_buf_wr_en=0). Active write/fetch stimulus "
                    "(list_buf_wr_en=1, list_fetch, or named check task) "
                    "is required. "
                    "Add PRP list load interface test or document as Accepted Limitation.")
            else:
                findings.append(
                    "Storage mover evidence: PRP list support claimed but TB "
                    "has no public list_buf_wr_en/list_buf_idx/list_buf_data "
                    "handshake exercise. Hierarchical dut.* writes are not "
                    "public interface evidence. "
                    "Add PRP list load interface test or document as Accepted Limitation.")

    # --- T10/T11/WSTRB/shape coverage claims without markers ---
    doc_claims_shape = bool(re.search(
        r'\b(?:T10|T11|shape.scoreboard|transaction.shape|'
        r'AWADDR.*AWLEN.*WSTRB|WSTRB.*coverage)\b',
        all_doc_text, re.IGNORECASE))
    if doc_claims_shape:
        tb_has_shape_markers = bool(re.search(
            r'\b(?:T10|T11|shape_scoreboard|txn_shape|'
            r'awaddr.*check|awlen.*check|wstrb.*check|wlast.*check)\b',
            combined_content, re.IGNORECASE))
        if not tb_has_shape_markers:
            findings.append(
                "Storage mover evidence: docs claim T10/T11/WSTRB/shape "
                "coverage but TB/sim logs have no corresponding shape "
                "scoreboard markers. Doc claims are not execution evidence. "
                "Add transaction-shape scoreboard checks.")

    return findings


def check_invalid_command_completion(proj_dir: str) -> list[str]:
    """Invalid-command completion evidence gate for storage/NVMe projects.

    If docs or RTL mention invalid NSID, invalid command, or validation error
    together with a completion/status interface, require TB/sim evidence of an
    invalid-command test that waits for completion and checks nonzero
    cpl_status/status.  A bare error pulse without completion is not sufficient.
    """
    findings = []

    rtl_dir = os.path.join(proj_dir, 'rtl')
    docs_dir = os.path.join(proj_dir, 'docs')

    all_rtl_text = ''
    if os.path.isdir(rtl_dir):
        for fname in os.listdir(rtl_dir):
            if fname.endswith(('.v', '.sv')):
                all_rtl_text += _read_file(os.path.join(rtl_dir, fname)) + '\n'

    all_doc_text = ''
    for doc_name in ('SPEC.md', 'dev_log.md', 'protocol_claim_ledger.md',
                      'verification_matrix.md', 'interface-contracts.md'):
        all_doc_text += _read_file(os.path.join(docs_dir, doc_name)) + '\n'

    combined_text = all_rtl_text + '\n' + all_doc_text

    # Only activate for NVMe/storage contexts with completion/status interface
    has_nvme_context = bool(re.search(
        r'\b(nvme|nsid|cpl_status|prp|admin\s+cmd|io\s+cmd)\b',
        combined_text, re.IGNORECASE))
    has_completion_iface = bool(re.search(
        r'\b(?:cpl_status|completion|cpl_entry|status_field|done_o|'
        r'cpl_valid|completion_valid)\b',
        combined_text, re.IGNORECASE))
    if not (has_nvme_context and has_completion_iface):
        return findings

    # Check if docs/RTL mention invalid-command scenarios
    mentions_invalid = bool(re.search(
        r'\b(?:invalid\s+(?:nsid|command|cmd|opcode)|'
        r'invalid\s+namespace|unknown\s+opcode|unsupported\s+command|'
        r'command\s+validation|cmd\s+error|invalid\s+request)\b',
        combined_text, re.IGNORECASE))
    # Also check for explicit error-status scenarios
    mentions_error_status = bool(re.search(
        r'\b(?:error\s+status|invalid\s+status|cpl_status\s*(?:!=|!==|==)\s*(?:0|2|4)|'
        r'status_code|SC_|generic\s+command\s+status)\b',
        combined_text, re.IGNORECASE))

    if not (mentions_invalid or mentions_error_status):
        return findings

    # Docs/RTL claim invalid-command handling.  Now check TB/sim evidence.
    combined_content, tb_warnings = _collect_tb_and_sim_content(proj_dir)

    # Evidence required: an invalid-command test that:
    #   1. Sends an invalid NSID/command/opcode
    #   2. Waits for completion
    #   3. Checks nonzero cpl_status or error status
    # Pattern: test sends invalid cmd, then checks status/cpl_status != 0 or
    # checks for specific error status codes.
    has_invalid_cmd_test = bool(re.search(
        r'\b(?:test_invalid|check_invalid|test_bad|check_bad|'
        r'test_error_cmd|check_error_cmd|test_unknown_opcode|'
        r'test_invalid_nsid|check_invalid_nsid)\b',
        combined_content, re.IGNORECASE))
    # Alternative: inline test that injects invalid NSID/opcode and checks completion
    has_inline_invalid_test = bool(re.search(
        r'\b(?:invalid|bad|unknown)\s*(?:nsid|cmd|opcode|command)\b'
        r'[^;]{0,200}'
        r'\b(?:cpl_status|status|completion)\s*(?:!=|!==|==|===)\s*(?!0\b)',
        combined_content, re.IGNORECASE | re.DOTALL))
    # Alternative: wait for completion after invalid command + check status
    has_wait_and_check = bool(re.search(
        r'\b(?:invalid|bad)\b[^;]{0,100}\bnsid\b'
        r'[^;]{0,300}'
        r'\b(?:wait|@(?:posedge|negedge))\b[^;]{0,200}'
        r'\b(?:cpl_status|status)\b[^;]{0,50}(?:!=|!==)\s*0',
        combined_content, re.IGNORECASE | re.DOTALL))
    # Check for TEST_PASS markers for invalid-command tests
    has_invalid_test_pass = bool(re.search(
        r'TEST_PASS\s+\w*(?:invalid|bad_ns|error_cmd|unknown_opcode)\w*',
        combined_content, re.IGNORECASE))

    if not (has_invalid_cmd_test or has_inline_invalid_test or
            has_wait_and_check or has_invalid_test_pass):
        findings.append(
            "Invalid-command completion evidence: docs/RTL mention invalid "
            "NSID/command/validation error with completion interface, but TB "
            "has no invalid-command test that waits for completion and checks "
            "nonzero cpl_status/status. A bare error pulse without completion "
            "is not sufficient. "
            "Add invalid-command completion test or mark as Accepted Limitation.")

    return findings


def check_tbd_docs(proj_dir: str) -> list[str]:
    """Scan docs/ for TBD/placeholder content when Status claims PASS or COMPLETE.

    Checks SPEC.md, dev_log.md, interface-contracts.md, timing-contract.md,
    protocol_claim_ledger.md, verification_matrix.md, and
    contract_implementation_matrix.md for:
      - Literal TBD / 'To be filled' / 'TODO: fill' placeholder text.
      - A 'Final Summary' heading with empty/no substantive content after it.
    Reports FAIL if any such content is found AND dev_log Status is PASS or COMPLETE.
    """
    findings = []

    dev_log = os.path.join(proj_dir, 'docs', 'dev_log.md')
    if not os.path.isfile(dev_log):
        return findings

    with open(dev_log, 'r', encoding='utf-8', errors='replace') as f:
        text = f.read()

    status_match = re.search(r'Status:\s*(PASS|COMPLETE)', text, re.IGNORECASE)
    if not status_match:
        return findings

    status = status_match.group(1)

    docs_dir = os.path.join(proj_dir, 'docs')
    if not os.path.isdir(docs_dir):
        return findings

    docs_to_check = [
        'SPEC.md',
        'dev_log.md',
        'interface-contracts.md',
        'timing-contract.md',
        'protocol_claim_ledger.md',
        'verification_matrix.md',
        'contract_implementation_matrix.md',
    ]

    for doc_name in docs_to_check:
        doc_path = os.path.join(docs_dir, doc_name)
        if not os.path.isfile(doc_path):
            continue

        with open(doc_path, 'r', encoding='utf-8', errors='replace') as f:
            doc_text = f.read()

        # Check for explicit TBD/placeholder markers
        if re.search(r'\bTBD\b|\bTo be filled\b|\bTODO:\s*fill\b', doc_text, re.IGNORECASE):
            findings.append(
                f"Document {doc_name} contains TBD/placeholder content "
                f"while Status claims {status}.")
            continue

        # Check for empty/near-empty Final Summary section
        summary_match = re.search(
            r'^#{1,6}\s+Final\s+Summary\s*$',
            doc_text, re.IGNORECASE | re.MULTILINE)
        if summary_match:
            after_summary = doc_text[summary_match.end():].strip()
            # Truncate at next heading, if any
            next_heading = re.search(r'^#{1,6}\s+', after_summary, re.MULTILINE)
            if next_heading:
                after_summary = after_summary[:next_heading.start()].strip()
            if not after_summary or len(after_summary) < 10:
                findings.append(
                    f"Document {doc_name} has empty Final Summary section "
                    f"while Status claims {status}.")

    return findings


def check_workflow_state_consistency(proj_dir: str) -> list[str]:
    """Check that PASS claims in dev_log are consistent with workflow_state.

    If workflow_state.json exists and shows FAIL or missing phases, a
    Status: PASS in dev_log is invalid.
    """
    findings = []
    state_path = os.path.join(proj_dir, 'docs', 'workflow_state.json')
    if not os.path.isfile(state_path):
        return findings  # No state file to cross-check

    try:
        with open(state_path, 'r', encoding='utf-8', errors='replace') as f:
            state = json.load(f)
    except (json.JSONDecodeError, OSError):
        return findings

    phases = state.get('phases', {})
    if not phases:
        return findings

    # Check if any phase has FAIL status
    failed_phases = [p for p, e in phases.items() if e.get('status') == 'FAIL']
    if not failed_phases:
        return findings

    # Check if dev_log claims PASS despite phase failures
    dev_log = os.path.join(proj_dir, 'docs', 'dev_log.md')
    if not os.path.isfile(dev_log):
        dev_log = os.path.join(proj_dir, 'dev_log.md')

    if os.path.isfile(dev_log):
        with open(dev_log, 'r', encoding='utf-8', errors='replace') as f:
            dev_text = f.read()
        if re.search(r'Status:\s*(PASS|COMPLETE)', dev_text, re.IGNORECASE):
            findings.append(
                f"WORKFLOW_STATE_INCONSISTENCY: dev_log claims Status: PASS "
                f"but workflow_state.json shows FAIL for phase(s): "
                f"{', '.join(failed_phases)}. "
                f"Re-run failed phase gates before claiming PASS. "
                f"Allowed statuses when gates fail: BLOCKED, FAIL, "
                f"BLOCKED_BY_GATE_DISPUTE.")

    return findings


def main():
    parser = argparse.ArgumentParser(
        description="Project artifact gate: verify required documents and evidence cross-check.")
    parser.add_argument('project_dir', help='Project directory to check')
    args = parser.parse_args()

    proj_dir = args.project_dir
    if not os.path.isdir(proj_dir):
        print(f"[REJECT] Not a directory: {proj_dir}", file=sys.stderr)
        sys.exit(1)

    level, has_user_spec = find_level_and_spec(proj_dir)
    print(f"Detected level: {level}, user-spec: {has_user_spec}")

    findings = check_artifacts(proj_dir, level, has_user_spec)
    findings.extend(check_workflow_state_consistency(proj_dir))
    findings.extend(check_evidence_cross_ref(proj_dir))
    findings.extend(check_verification_matrix_evidence(proj_dir))
    findings.extend(check_module_verification_evidence(proj_dir, level))
    findings.extend(check_delegation_evidence(proj_dir, level))
    findings.extend(check_residual_risks(proj_dir))
    findings.extend(check_tbd_docs(proj_dir))
    findings.extend(check_scoreboard_substance(proj_dir))
    findings.extend(check_prp_feature_claims(proj_dir))
    findings.extend(check_protocol_claim_ledger_evidence(proj_dir))
    findings.extend(check_storage_mover_evidence(proj_dir))
    findings.extend(check_invalid_command_completion(proj_dir))

    if not findings:
        print("PROJECT_ARTIFACT_GATE: PASS")
        sys.exit(0)

    print("PROJECT_ARTIFACT_GATE: FAIL")
    for f in findings:
        print(f"  - {f}")
    sys.exit(1)


if __name__ == '__main__':
    main()
