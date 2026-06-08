"""Simulation log gate: reject false-pass simulation outputs.

Exit 0 only when ALL conditions are true:
  - log contains ALL_TESTS_PASS
  - log contains SIMULATION_DONE
  - log does not contain TIMEOUT, FAIL, FATAL, mismatch, unknown, xxxx,
    or x/z evidence outside benign explanatory text
  - log does not contain contradictory PASS evidence such as WLAST=0
    transaction-shape summaries or unexplained duplicate completions

Exit 1 with clear findings otherwise.

Usage: python scripts/sim_log_gate.py <sim_log_file>
"""
import argparse
import io
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

# Patterns that indicate a hard failure or false-pass risk.
FAIL_PATTERNS = [
    (re.compile(r'\bTIMEOUT\b', re.IGNORECASE), "TIMEOUT marker present"),
    (re.compile(r'TESTS_FAILED', re.IGNORECASE), "TESTS_FAILED found"),
    (re.compile(r'TEST_FAIL\b', re.IGNORECASE), "TEST_FAIL found"),
    (re.compile(r'\bFAIL\b', re.IGNORECASE), "FAIL keyword found"),
    (re.compile(r'^\s*FATAL\b', re.MULTILINE | re.IGNORECASE), "FATAL message found"),
    (re.compile(r'mismatch', re.IGNORECASE), "mismatch keyword found"),
    (re.compile(r'unknown', re.IGNORECASE), "unknown keyword found"),
    (re.compile(r'xxxx', re.IGNORECASE), "xxxx found (possible X-injection)"),
]

# Single-char x/z detection in hex-looking context.  Conservative: only match
# when inside a hex literal or quoted value to avoid false positives on prose.
XZ_PATTERN = re.compile(
    r"['\"]?\b[0-9]*'[bBhHdD][0-9a-fA-FxXzZ]+|"
    r"===?\s*\d+'[bBhHdD][xXzZ]+|"
    r"!==?\s*\d+'[bBhHdD][0-9a-fA-F]+"
)

PASS_PATTERN = re.compile(r'ALL_TESTS_PASS', re.IGNORECASE)
DONE_PATTERN = re.compile(r'SIMULATION_DONE', re.IGNORECASE)
EXPECTED_MULTI_COMPLETION_PATTERN = re.compile(
    r'EXPECTED_CPL|expected[_\s-]*(?:completion|cpl)s?\s*[:=]?\s*\d+|'
    r'multi[-\s]?completion|completion\s+ordering|ordering',
    re.IGNORECASE)


def is_benign_failure_line(line: str) -> bool:
    """Return True for wrapper metadata lines that mention timeout settings.

    Do not suppress real guarded-wrapper failures such as
    "RUN_SIM_GUARDED: TIMEOUT ..." or "RUN_SIM_GUARDED: FAIL ...".

    Expected timeout-protection test text (e.g. "status=TIMEOUT",
    "TEST_PASS timeout_protection") is allowed only when ALL_TESTS_PASS and
    SIMULATION_DONE are present in the log.
    """
    stripped = line.lstrip()
    if stripped.startswith('#'):
        return True
    if not stripped.startswith('RUN_SIM_GUARDED:'):
        return False
    if re.search(r'RUN_SIM_GUARDED:\s*(TIMEOUT|FAIL)\b',
                 stripped, re.IGNORECASE):
        return False
    if re.search(r'\b(timeout=\d+s|command=|elapsed=|vvp_exit=0|PASS)\b',
                 stripped, re.IGNORECASE):
        return True
    return False


def is_expected_timeout_context(line: str, has_pass: bool, has_done: bool) -> bool:
    """Return True if a TIMEOUT mention is part of an expected timeout-protection test.

    Only allowed when ALL_TESTS_PASS and SIMULATION_DONE both exist, and the
    timeout wording is tied to TEST_PASS/expected/status=TIMEOUT patterns,
    NOT to RUN_SIM_GUARDED timeout or watchdog failure.
    """
    if not (has_pass and has_done):
        return False
    # Must be tied to expected/test-pass context
    return bool(re.search(
        r'(TEST_PASS.*timeout|timeout.*TEST_PASS|'
        r'status\s*=\s*TIMEOUT|expected.*timeout|'
        r'timeout_protection.*PASS|PASS.*timeout_protection)',
        line, re.IGNORECASE))


def check_log(text: str) -> list[str]:
    """Return list of findings. Empty list means PASS."""
    findings = []

    has_pass = bool(PASS_PATTERN.search(text))
    has_done = bool(DONE_PATTERN.search(text))

    if not has_pass:
        findings.append("Missing ALL_TESTS_PASS in log")
    if not has_done:
        findings.append("Missing SIMULATION_DONE in log (possible hang)")

    for pat, desc in FAIL_PATTERNS:
        m = pat.search(text)
        if m:
            # Check if the match is on a benign metadata line (e.g.
            # "RUN_SIM_GUARDED: command=... timeout=30s").
            line_start = text.rfind('\n', 0, m.start()) + 1
            line_end = text.find('\n', m.end())
            if line_end == -1:
                line_end = len(text)
            line = text[line_start:line_end]
            if is_benign_failure_line(line):
                continue
            # Check if this is an expected timeout-protection test
            if (desc == "TIMEOUT marker present" and
                    is_expected_timeout_context(line, has_pass, has_done)):
                continue
            findings.append(f"REJECT: {desc}")

    # X/Z check: flag only when x/z appears in value context, not in prose.
    for m in XZ_PATTERN.finditer(text):
        token = m.group(0)
        # Skip benign explanations like "avoid x/z" or "no x/z"
        start = max(0, m.start() - 40)
        ctx = text[start:m.start()].lower()
        if any(kw in ctx for kw in ['avoid', 'no x', 'without x', 'prevent x']):
            continue
        findings.append(f"X/Z value detected: {token!r}")
        break  # one is enough

    findings.extend(check_semantic_contradictions(text))
    findings.extend(check_cpl_zero_byte_success(text))

    return findings


def check_cpl_zero_byte_success(text: str) -> list[str]:
    """SIM_CPL_ZERO1: reject PASS logs with successful completion but bytes=0.

    For DMA/mover projects, a completion entry showing status=0 (success) and
    bytes=0 is a strong false-pass indicator unless the test is explicitly a
    zero-byte transfer test.  A successfully completed DMA transfer must have
    moved non-zero bytes (except for intentional zero-length descriptor tests).
    """
    findings: list[str] = []

    # Look for completion summary patterns like:
    #   CPL[0]: status=0, bytes=0
    #   Completion: status=00, bytes_written=00000000
    #   cpl_status=0 cpl_bytes=0
    # Match (status=0, bytes=0) or (bytes=0, status=0) in any order.
    zero_byte_success = re.findall(
        r'CPL\[\d+\][^;\n]*'
        r'(?:status\s*=\s*0[^;\n]*bytes\s*=\s*0|'
        r'bytes\s*=\s*0[^;\n]*status\s*=\s*0)',
        text, re.IGNORECASE)

    if not zero_byte_success:
        zero_byte_success = re.findall(
            r'(?:cpl_status|cpl_status_o|status_o)\s*[=:]\s*0[^;\n]*'
            r'(?:cpl_bytes|cpl_byte|bytes_written)\s*[=:]\s*0|'
            r'(?:cpl_bytes|cpl_byte|bytes_written)\s*[=:]\s*0[^;\n]*'
            r'(?:cpl_status|cpl_status_o|status_o)\s*[=:]\s*0|'
            r'(?:completion|done)\s*:[^;\n]*'
            r'(?:status\s*[=:]\s*0[^;\n]*bytes\s*[=:]\s*0|'
            r'bytes\s*[=:]\s*0[^;\n]*status\s*[=:]\s*0)',
            text, re.IGNORECASE)

    if not zero_byte_success:
        return findings

    has_zero_byte_test = bool(re.search(
        r'\b(zero[-\s]?(?:byte|length|transfer)|'
        r'0[-\s]?byte\s+(?:transfer|test|descriptor)|'
        r'empty\s+(?:transfer|descriptor)|'
        r'null\s+descriptor)\b',
        text, re.IGNORECASE))

    if has_zero_byte_test:
        return findings

    findings.append(
        "SIM_CPL_ZERO1: completion with status=0 (success) and bytes=0 "
        "found in PASS log, but no zero-byte transfer test is declared. "
        "A DMA mover reporting successful completion with zero bytes moved "
        "indicates cpl_bytes is not being populated correctly, or the TB "
        "is not checking completion bytes. "
        "Either: fix cpl_bytes RTL wiring, add cpl_bytes comparison in TB, "
        "or declare an explicit zero-byte transfer test if intentional.")
    return findings


def check_semantic_contradictions(text: str) -> list[str]:
    """Reject PASS logs whose own summaries contradict the expected behavior.

    This is intentionally semantic and conservative: it targets compact
    transaction-shape summaries commonly printed by storage/DMA TBs, where a
    PASS can be meaningless if the summary says WLAST never asserted or a
    single command produced duplicate completions.
    """
    findings: list[str] = []

    for line_no, line in enumerate(text.splitlines(), 1):
        if not re.search(r'\bShape\b\s*:', line, re.IGNORECASE):
            continue
        m = re.search(r'\bWLAST\s*=\s*([01xXzZ]+)\b', line)
        if not m:
            continue
        value = m.group(1).lower()
        if value == '0':
            findings.append(
                f"REJECT: line {line_no} reports transaction shape WLAST=0 "
                "while log claims PASS")
        elif re.search(r'[xz]', value):
            findings.append(
                f"REJECT: line {line_no} reports transaction shape WLAST={m.group(1)} "
                "while log claims PASS")

    cpl_indices = [
        int(m.group(1))
        for m in re.finditer(r'^\s*CPL\[(\d+)\]', text, re.MULTILINE)
    ]
    if cpl_indices and max(cpl_indices) > 1:
        if not EXPECTED_MULTI_COMPLETION_PATTERN.search(text):
            findings.append(
                f"REJECT: CPL[{max(cpl_indices)}] appears but the log has no "
                "expected multi-completion marker; possible duplicate completion false-pass")

    return findings


def read_log_text(log_file: str) -> str:
    """Read logs produced by shells/tools with UTF-8, UTF-16, or mixed bytes."""
    with open(log_file, 'rb') as f:
        data = f.read()

    for enc in ('utf-8-sig', 'utf-16', 'utf-16-le', 'utf-16-be'):
        try:
            text = data.decode(enc)
        except UnicodeError:
            continue
        # Prefer a decode that does not leave every ASCII character separated by NUL.
        if text.count('\x00') <= max(4, len(text) // 20):
            return text

    text = data.decode('utf-8', errors='replace')
    if '\x00' in text:
        text = text.replace('\x00', '')
    return text


def main():
    parser = argparse.ArgumentParser(
        description="Simulation log gate: reject false-pass outputs.")
    parser.add_argument('log_file', help='Simulation log file to check')
    args = parser.parse_args()

    try:
        text = read_log_text(args.log_file)
    except FileNotFoundError:
        print(f"[REJECT] File not found: {args.log_file}", file=sys.stderr)
        sys.exit(1)

    findings = check_log(text)

    if not findings:
        print("SIM_LOG_GATE: PASS")
        sys.exit(0)

    print("SIM_LOG_GATE: FAIL")
    for f in findings:
        print(f"  - {f}")
    sys.exit(1)


if __name__ == '__main__':
    main()
