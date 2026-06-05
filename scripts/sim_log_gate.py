"""Simulation log gate: reject false-pass simulation outputs.

Exit 0 only when ALL conditions are true:
  - log contains ALL_TESTS_PASS
  - log contains SIMULATION_DONE
  - log does not contain TIMEOUT, FAIL, FATAL, mismatch, unknown, xxxx,
    or x/z evidence outside benign explanatory text

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
